--- Тесты документа: объявленные маршруты и описания — OpenAPI целиком.

local json = require('json')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.openapi.document')

local openapi = helper.openapi
local data = helper.data

--- Ссылка на схему формы.
---@param name string
---@return table
local function ref(name)
    return { ['$ref'] = '#/components/schemas/' .. name }
end

--- Тело JSON со схемой.
---@param schema table
---@param media string|nil
---@return table
local function content(schema, media)
    return { [media or 'application/json'] = { schema = schema } }
end

--- Ответ `default` без тела отказа.
local DEFAULT = { description = 'Отказ, не названный у операции' }

--- Параметр пути.
---@param name string
---@param schema table
---@param description string|nil
---@return table
local function param(name, schema, description)
    return { name = name, ['in'] = 'path', required = true, schema = schema, description = description }
end

--- Документ либо провал проверки с расхождениями.
---
--- Род у документа любой: проверки лезут в него по путям, которых
--- анализатор типов знать не может.
---@param api TntOpenapi
---@param router table
---@return any
local function built(api, router)
    local document, problems = api.document(router)

    t.assert_equals(problems, nil)

    return document
end

--- Расхождения документа.
---@param api TntOpenapi
---@param router table
---@return string[]
local function drift(api, router)
    local document, problems = api.document(router)

    t.assert_equals(document, nil)

    return problems --[[@as string[] ]]
end

--- Формы проверок: адрес вложен в клиента.
---@type TntDataShape<table>
local Address

---@type TntDataShape<table>
local Customer

---@type TntDataShape<table>
local NewCustomer

---@type TntDataShape<table>
local Problem

helper.declare(g, function()
    Address = data.define({ name = 'Address', fields = { { 'city', 'string' } } })
    Customer = data.define({
        name = 'Customer',
        about = 'Клиент',
        fields = { { 'id', 'integer', min = 1 }, { 'address', Address, optional = true } },
    })
    NewCustomer = data.define({ name = 'NewCustomer', fields = { { 'name', 'string', max = 64 } } })
    Problem = data.define({ name = 'Problem', fields = { { 'title', 'string' }, { 'status', 'integer' } } })
end)

g.test_document_follows_routes_forms_and_query = function()
    local Customers = helper.query.define({ shape = NewCustomer, filters = { 'name' } })
    local router = helper.routed(function(r)
        r.group('/api/v1', function(api)
            api.get('/customers', helper.handler, { name = 'customers.list' })
            api.get('/customers/:id<int>', helper.handler, { name = 'customers.show' })
            api.post('/customers', helper.handler, { name = 'customers.create' })
        end)
        r.get('/metrics', helper.handler, { name = 'metrics' })
        -- Страница без имени — не API: описания у неё нет, и отказа нет.
        r.get('/', helper.handler)
    end)

    local api = openapi.define({
        title = 'Магазин',
        version = '1.2',
        description = 'Клиенты и заказы',
        servers = { { url = 'https://shop.example.org/api/v1/', description = 'бой' } },
        refusal = { schema = Problem, media = 'application/problem+json', description = 'Прочий отказ' },
        security = { { session = {} } },
        security_schemes = { session = { type = 'apiKey', ['in'] = 'cookie', name = 'sid' } },
        operations = {
            ['customers.list'] = {
                summary = 'Клиенты',
                tags = { 'customers' },
                query = Customers,
                responses = {
                    [200] = { description = 'Страница', schema = { type = 'array', items = Customer } },
                },
            },
            ['customers.show'] = {
                summary = 'Клиент по номеру',
                description = 'Ищет по номеру',
                params = { id = 'Номер клиента' },
                responses = { [200] = Customer, [404] = 'Клиента нет' },
            },
            ['customers.create'] = {
                summary = 'Завести клиента',
                deprecated = true,
                body = NewCustomer,
                responses = { [201] = Customer, [422] = { description = 'Не прошло', schema = Problem } },
            },
            metrics = {
                summary = 'Метрики',
                security = {},
                responses = {
                    [200] = { description = 'Текст', schema = { type = 'string' }, media = 'text/plain' },
                },
            },
        },
    })

    local refusal = content(ref('Problem'), 'application/problem+json')
    local default = { description = 'Прочий отказ', content = refusal }

    t.assert_equals(built(api, router), {
        openapi = '3.0.3',
        info = { title = 'Магазин', version = '1.2', description = 'Клиенты и заказы' },
        servers = { { url = 'https://shop.example.org/api/v1/', description = 'бой' } },
        security = { { session = {} } },
        paths = {
            ['/customers'] = {
                get = {
                    operationId = 'customers.list',
                    summary = 'Клиенты',
                    tags = { 'customers' },
                    parameters = Customers.parameters(),
                    responses = {
                        ['200'] = {
                            description = 'Страница',
                            content = content({ type = 'array', items = ref('Customer') }),
                        },
                        default = default,
                    },
                },
                post = {
                    operationId = 'customers.create',
                    summary = 'Завести клиента',
                    deprecated = true,
                    requestBody = { required = true, content = content(ref('NewCustomer')) },
                    responses = {
                        ['201'] = { description = 'Клиент', content = content(ref('Customer')) },
                        ['422'] = { description = 'Не прошло', content = content(ref('Problem')) },
                        default = default,
                    },
                },
            },
            ['/customers/{id}'] = {
                get = {
                    operationId = 'customers.show',
                    summary = 'Клиент по номеру',
                    description = 'Ищет по номеру',
                    parameters = { param('id', { type = 'integer' }, 'Номер клиента') },
                    responses = {
                        ['200'] = { description = 'Клиент', content = content(ref('Customer')) },
                        ['404'] = { description = 'Клиента нет', content = refusal },
                        default = default,
                    },
                },
            },
            ['/metrics'] = {
                -- Вне начала сервера: путь целиком и свой сервер — корень узла.
                servers = { { url = 'https://shop.example.org/' } },
                get = {
                    operationId = 'metrics',
                    summary = 'Метрики',
                    security = {},
                    responses = {
                        ['200'] = { description = 'Текст', content = content({ type = 'string' }, 'text/plain') },
                        default = default,
                    },
                },
            },
        },
        components = {
            schemas = {
                Address = Address.schema(),
                Customer = Customer.schema(),
                NewCustomer = NewCustomer.schema(),
                Problem = Problem.schema(),
            },
            securitySchemes = { session = { type = 'apiKey', ['in'] = 'cookie', name = 'sid' } },
        },
    })
end

g.test_a_list_response_is_described_by_its_query = function()
    local Customers = helper.query.define({ shape = NewCustomer, filters = { 'name' } })
    local router = helper.routed(function(r)
        r.get('/customers', helper.handler, { name = 'customers.list' })
    end)
    local api = openapi.define(helper.spec({
        ['customers.list'] = {
            query = Customers,
            responses = { [200] = { description = 'Клиенты', schema = Customers.schema(Customer) } },
        },
    }))
    local document = built(api, router)
    local listed = document.paths['/customers'].get.responses['200'].content['application/json'].schema

    -- Запись списка — форма: в документе она ссылка, а схема — в components.
    t.assert_equals(listed, Customers.schema(ref('Customer')))
    t.assert_equals(document.components.schemas, { Address = Address.schema(), Customer = Customer.schema() })

    local decoded = json.decode(json.encode(listed))

    t.assert_equals(decoded.properties.data.items, ref('Customer'))
    t.assert_equals(
        decoded.properties.links.properties.last.enum,
        { json.NULL },
        'всегда пустое поле уходит в JSON перечнем из одного null'
    )
end

g.test_document_without_servers_keeps_full_paths = function()
    local router = helper.routed(function(r)
        r.delete('/api/customers/:id<uuid>', helper.handler, { name = 'customers.remove' })
    end)
    local api = openapi.define(helper.spec({
        ['customers.remove'] = {
            responses = { [204] = 'Удалён', [404] = 'Нет такого', ['5XX'] = 'Сбой' },
        },
    }))

    t.assert_equals(built(api, router), {
        openapi = '3.0.3',
        info = { title = 'Магазин', version = '1' },
        paths = {
            ['/api/customers/{id}'] = {
                delete = {
                    operationId = 'customers.remove',
                    parameters = { param('id', { type = 'string', format = 'uuid' }) },
                    -- Без тела отказа у описания отказ описан одним словом.
                    responses = {
                        ['204'] = { description = 'Удалён' },
                        ['404'] = { description = 'Нет такого' },
                        ['5XX'] = { description = 'Сбой' },
                        default = DEFAULT,
                    },
                },
            },
        },
    })
end

g.test_empty_api_has_paths_as_an_object = function()
    local document = built(openapi.define(helper.spec({})), helper.routed(function() end))

    t.assert_equals(document.paths, {})
    t.assert_equals(document.components, nil)
    t.assert_equals(json.decode(json.encode(document)).paths, {})
    t.assert_str_contains(json.encode(document), '"paths":{}')
end

g.test_refusal_given_as_a_shape = function()
    local router = helper.routed(function(r)
        r.get('/a', helper.handler, { name = 'a' })
    end)
    local api = openapi.define(helper.spec({
        a = {
            responses = {
                [101] = 'Переключаю',
                [200] = 'Да',
                [301] = 'Переехал',
                [409] = 'Занято',
                ['4XX'] = 'Прочее',
                [503] = 'Закрыто',
                ['5XX'] = 'Сбой',
            },
        },
    }, { refusal = Problem }))

    -- Тело отказа — у 4xx и 5xx, и числом, и диапазоном, а у прочих нет.
    t.assert_equals(built(api, router).paths['/a'].get.responses, {
        ['101'] = { description = 'Переключаю' },
        ['200'] = { description = 'Да' },
        ['301'] = { description = 'Переехал' },
        ['409'] = { description = 'Занято', content = content(ref('Problem')) },
        ['4XX'] = { description = 'Прочее', content = content(ref('Problem')) },
        ['503'] = { description = 'Закрыто', content = content(ref('Problem')) },
        ['5XX'] = { description = 'Сбой', content = content(ref('Problem')) },
        default = {
            description = 'Отказ, не названный у операции',
            content = content(ref('Problem')),
        },
    })
end

g.test_named_default_and_own_refusal_body_stay = function()
    local router = helper.routed(function(r)
        r.get('/a', helper.handler, { name = 'a' })
    end)
    local api = openapi.define(helper.spec({
        a = {
            responses = {
                [200] = Customer,
                [400] = { description = 'Разбор', schema = Customer },
                default = 'Что угодно',
            },
        },
    }, { refusal = Problem }))

    t.assert_equals(built(api, router).paths['/a'].get.responses, {
        ['200'] = { description = 'Клиент', content = content(ref('Customer')) },
        ['400'] = { description = 'Разбор', content = content(ref('Customer')) },
        default = { description = 'Что угодно', content = content(ref('Problem')) },
    })
end

g.test_shape_without_about_is_described_by_name = function()
    local router = helper.routed(function(r)
        r.put('/a', helper.handler, { name = 'a' })
    end)
    local api = openapi.define(helper.spec({ a = { responses = { [200] = Problem } } }))

    t.assert_equals(built(api, router).paths['/a'].put.responses['200'], {
        description = 'Problem',
        content = content(ref('Problem')),
    })
end

g.test_body_given_as_a_table = function()
    local router = helper.routed(function(r)
        r.patch('/a', helper.handler, { name = 'a' })
        r.post('/b', helper.handler, { name = 'b' })
    end)
    local api = openapi.define(helper.spec({
        a = {
            body = {
                schema = NewCustomer,
                media = 'application/merge-patch+json',
                description = 'Правка',
                optional = true,
            },
            responses = { [200] = 'Да' },
        },
        b = { body = { schema = { type = 'string' } }, responses = { [200] = 'Да' } },
    }))
    local document = built(api, router)

    t.assert_equals(document.paths['/a'].patch.requestBody, {
        description = 'Правка',
        required = false,
        content = content(ref('NewCustomer'), 'application/merge-patch+json'),
    })
    t.assert_equals(document.paths['/b'].post.requestBody, {
        required = true,
        content = content({ type = 'string' }),
    })
end

g.test_shapes_inside_raw_schemas_and_parameters_become_references = function()
    local marked = setmetatable({}, { __serialize = 'map' })
    local router = helper.routed(function(r)
        r.get('/a/:id', helper.handler, { name = 'a' })
    end)
    local api = openapi.define(helper.spec({
        a = {
            parameters = { { name = 'filter', ['in'] = 'query', schema = Address } },
            responses = {
                [200] = {
                    description = 'Всё',
                    schema = {
                        type = 'object',
                        properties = { list = { type = 'array', items = NewCustomer } },
                        additionalProperties = marked,
                    },
                },
            },
        },
    }))
    local operation = built(api, router).paths['/a/{id}'].get

    t.assert_equals(operation.parameters, {
        param('id', { type = 'string' }),
        { name = 'filter', ['in'] = 'query', schema = ref('Address') },
    })
    t.assert_equals(operation.responses['200'].content['application/json'].schema, {
        type = 'object',
        properties = { list = { type = 'array', items = ref('NewCustomer') } },
        additionalProperties = {},
    })
    -- Разметка пустого словаря доезжает до документа: в JSON он объект.
    t.assert_str_contains(json.encode(operation.responses['200']), '"additionalProperties":{}')
end

g.test_nested_shapes_reach_components = function()
    local router = helper.routed(function(r)
        r.get('/a', helper.handler, { name = 'a' })
    end)
    local document = built(openapi.define(helper.spec({ a = { responses = { [200] = Customer } } })), router)

    t.assert_equals(document.components, {
        schemas = { Customer = Customer.schema(), Address = Address.schema() },
    })
end

g.test_optional_segment_gives_paths_with_one_identifier = function()
    local router = helper.routed(function(r)
        r.get('/files/:name?', helper.handler, { name = 'files' })
    end)
    local api = openapi.define(helper.spec({
        files = { params = { name = 'Имя файла' }, responses = { [200] = 'Файл' } },
    }))

    t.assert_equals(built(api, router).paths, {
        ['/files/{name}'] = {
            get = {
                operationId = 'files',
                parameters = { param('name', { type = 'string' }, 'Имя файла') },
                responses = { ['200'] = { description = 'Файл' }, default = DEFAULT },
            },
        },
        ['/files'] = {
            get = { responses = { ['200'] = { description = 'Файл' }, default = DEFAULT } },
        },
    })
end

g.test_head_and_options_are_their_own_operations = function()
    local router = helper.routed(function(r)
        r.head('/a', helper.handler, { name = 'a.head' })
        r.options('/a', helper.handler, { name = 'a.options' })
    end)
    local api = openapi.define(helper.spec({
        ['a.head'] = { responses = { [200] = 'Есть' } },
        ['a.options'] = { responses = { [204] = 'Способы' } },
    }))
    local item = built(api, router).paths['/a']

    t.assert_equals(item.head.operationId, 'a.head')
    t.assert_equals(item.options.operationId, 'a.options')
end

g.test_server_path_itself_is_the_slash = function()
    local router = helper.routed(function(r)
        r.get('/api', helper.handler, { name = 'root' })
    end)
    local api =
        openapi.define(helper.spec({ root = { responses = { [200] = 'Да' } } }, { servers = { { url = '/api' } } }))

    t.assert_equals(built(api, router).paths, {
        ['/'] = {
            get = { operationId = 'root', responses = { ['200'] = { description = 'Да' }, default = DEFAULT } },
        },
    })
end

g.test_path_outside_relative_server_gets_the_root = function()
    local router = helper.routed(function(r)
        r.get('/health', helper.handler, { name = 'health' })
    end)
    local api = openapi.define(
        helper.spec({ health = { responses = { [200] = 'Жив' } } }, { servers = { { url = '/api' } } })
    )

    t.assert_equals(built(api, router).paths['/health'].servers, { { url = '/' } })
end

g.test_every_call_gives_its_own_document = function()
    local tags = { 'a' }
    local router = helper.routed(function(r)
        r.get('/a/:id<int>', helper.handler, { name = 'a' })
    end)
    local api = openapi.define(helper.spec({
        a = { tags = tags, responses = { [200] = Customer } },
    }, { servers = { { url = '/' } }, security = { { key = {} } } }))
    local first = built(api, router)

    first.paths['/a/{id}'].get.tags[1] = 'b'
    first.paths['/a/{id}'].get.parameters[1].schema.type = 'string'
    first.components.schemas.Customer.type = 'array'
    first.servers[1].url = '/x'
    first.security[1].key = nil
    tags[1] = 'c'

    local second = built(api, router)

    t.assert_equals(second.paths['/a/{id}'].get.tags, { 'a' })
    t.assert_equals(second.paths['/a/{id}'].get.parameters[1].schema, { type = 'integer' })
    t.assert_equals(second.components.schemas.Customer.type, 'object')
    t.assert_equals(second.servers, { { url = '/' } })
    t.assert_equals(second.security, { { key = {} } })
end

g.test_described_route_outside_the_selection_is_documented = function()
    local router = helper.routed(function(r)
        r.get('/api/a', helper.handler, { name = 'a' })
        r.get('/metrics', helper.handler, { name = 'metrics' })
        r.get('/page', helper.handler, { name = 'page' })
    end)
    local api = openapi.define(helper.spec({
        a = { responses = { [200] = 'Да' } },
        metrics = { responses = { [200] = 'Числа' } },
    }, {
        select = function(route)
            return route.pattern:find('^/api/') ~= nil
        end,
    }))

    t.assert_items_equals(helper.keys(built(api, router).paths), { '/api/a', '/metrics' })
end

g.test_every_problem_is_named_at_once = function()
    local router = helper.routed(function(r)
        r.get('/api/b', helper.handler, { name = 'b' })
        r.get('/api/c', helper.handler)
        r.get('/api/a', helper.handler, { name = 'a' })
        r.get('/page', helper.handler)
    end)
    local api = openapi.define(helper.spec({
        a = { responses = { [200] = 'Да' } },
        ghost = { responses = { [200] = 'Да' } },
        old = { responses = { [200] = 'Да' } },
    }, {
        select = function(route)
            return route.pattern:find('^/api/') ~= nil
        end,
    }))

    t.assert_equals(drift(api, router), {
        'Маршрут b (GET /api/b) не описан.',
        'Маршрут GET /api/c без имени: описание ищется по имени.',
        'Описание ghost: маршрута с таким именем нет.',
        'Описание old: маршрута с таким именем нет.',
    })
end

g.test_route_on_any_method_cannot_be_described = function()
    local router = helper.routed(function(r)
        r.any('/hook', helper.handler, { name = 'hook' })
    end)
    local api = openapi.define(helper.spec({ hook = { responses = { [200] = 'Да' } } }))

    t.assert_equals(drift(api, router), {
        'Маршрут hook (ANY /hook) объявлен на любой способ: описанию нужен способ.',
    })
end

g.test_word_for_a_missing_parameter_is_refused = function()
    local router = helper.routed(function(r)
        r.get('/a/:id', helper.handler, { name = 'a' })
    end)
    local api = openapi.define(helper.spec({
        a = { params = { uid = 'Номер', id = 'Номер', code = 'Код' }, responses = { [200] = 'Да' } },
    }))

    t.assert_equals(drift(api, router), {
        'Описание a: у маршрута нет параметра code.',
        'Описание a: у маршрута нет параметра uid.',
    })
end

g.test_two_routes_on_one_operation_are_refused = function()
    local router = helper.routed(function(r)
        r.get('/a/:id<int>', helper.handler, { name = 'by_number' })
        r.get('/a/:id<uuid>', helper.handler, { name = 'by_uuid' })
    end)
    local api = openapi.define(helper.spec({
        by_number = { responses = { [200] = 'Да' } },
        by_uuid = { responses = { [200] = 'Да' } },
    }))

    t.assert_equals(drift(api, router), {
        'Маршруты by_number (GET /a/:id<int>) и by_uuid (GET /a/:id<uuid>) дают одну операцию GET /a/{id}.',
    })
end
