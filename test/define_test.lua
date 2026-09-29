--- Тесты объявления описания: отказы при загрузке и место отказа.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.openapi.define')

local openapi = helper.openapi

--- Операция с одним ответом.
local PLAIN = { responses = { [200] = 'Да' } }

--- Отказ объявления описания с одной операцией `a`.
---@param entry any Объявление операции
---@return string
local function refused(entry)
    return helper.thrown(openapi.define, helper.spec({ a = entry }))
end

--- Отказ объявления операции с ответами `responses`.
---@param responses table
---@return string
local function refused_responses(responses)
    return refused({ responses = responses })
end

g.test_description_is_a_table = function()
    t.assert_equals(
        helper.thrown(openapi.define, helper.wrong(5)),
        'описание API — таблица, а не число'
    )
end

g.test_title_and_version_are_required = function()
    t.assert_equals(
        helper.thrown(openapi.define, { version = '1', operations = {} }),
        'описание API.title — непустая строка, а не nil'
    )
    t.assert_equals(
        helper.thrown(openapi.define, { title = 'Магазин', version = '', operations = {} }),
        'описание API.version — непустая строка, а не пустая'
    )
end

g.test_unknown_setting_is_refused = function()
    t.assert_equals(
        helper.thrown(openapi.define, helper.spec({}, { titel = 'Магазин' })),
        'описание API: ключа «titel» нет, есть description, operations, refusal, security, '
            .. 'security_schemes, select, servers, title, version'
    )
end

g.test_server_needs_its_address = function()
    t.assert_equals(
        helper.thrown(openapi.define, helper.spec({}, { servers = { { url = '' } } })),
        'описание API.servers[1].url — непустая строка, а не пустая'
    )
end

g.test_refusal_is_a_shape_or_a_table_with_schema = function()
    t.assert_equals(
        helper.thrown(openapi.define, helper.spec({}, { refusal = { media = 'application/problem+json' } })),
        'описание API.refusal.schema — таблица, а не nil'
    )
end

g.test_operation_name_is_a_non_empty_string = function()
    t.assert_equals(
        helper.thrown(openapi.define, helper.spec({ PLAIN })),
        'описание API.operations: имя маршрута — непустая строка, а не 1'
    )
    t.assert_equals(
        helper.thrown(openapi.define, helper.spec({ [''] = PLAIN })),
        'описание API.operations: имя маршрута — непустая строка, а не «»'
    )
end

g.test_unknown_operation_setting_is_refused = function()
    t.assert_equals(
        refused({ sumary = 'Клиенты', responses = { [200] = 'Да' } }),
        'операция «a»: ключа «sumary» нет, есть body, deprecated, description, parameters, params, '
            .. 'query, responses, security, summary, tags'
    )
end

g.test_first_wrong_operation_is_named_by_order = function()
    t.assert_equals(
        helper.thrown(openapi.define, helper.spec({ b = {}, a = {}, c = {} })),
        'операция «a».responses — таблица, а не nil'
    )
end

g.test_parameter_word_is_a_string = function()
    t.assert_equals(
        refused({ params = { id = 5 }, responses = { [200] = 'Да' } }),
        'операция «a».params.id — строка, а не число'
    )
end

g.test_query_is_a_declared_query = function()
    t.assert_equals(
        refused({ query = {}, responses = { [200] = 'Да' } }),
        'операция «a».query.parameters — функция или вызываемая таблица, а не nil'
    )
end

g.test_raw_parameters_are_tables = function()
    t.assert_equals(
        refused({ parameters = { 5 }, responses = { [200] = 'Да' } }),
        'операция «a».parameters[1] — таблица, а не число'
    )
end

g.test_body_is_a_shape_or_a_table_with_schema = function()
    t.assert_equals(
        refused({ body = { media = 'text/plain' }, responses = { [200] = 'Да' } }),
        'операция «a».body.schema — таблица, а не nil'
    )
end

g.test_operation_needs_a_response = function()
    t.assert_equals(
        refused_responses({}),
        'операция «a».responses — хотя бы один ответ, а не пустая таблица'
    )
end

g.test_response_code_is_checked = function()
    local complaint =
        'операция «a».responses: код ответа — целое от 100 до 599, «default» либо «4XX», а не %s'

    for _, case in ipairs({
        { 99, '99' },
        { 600, '600' },
        { 200.5, '200.5' },
        { '200', '«200»' },
        { '6XX', '«6XX»' },
        { '0XX', '«0XX»' },
        { '4XXX', '«4XXX»' },
        { 'X4XX', '«X4XX»' },
    }) do
        t.assert_equals(refused_responses({ [case[1]] = 'Отказ' }), complaint:format(case[2]), case[2])
    end
end

g.test_response_code_boundaries_pass = function()
    local api = openapi.define(helper.spec({
        a = { responses = { [100] = 'а', [599] = 'б', ['1XX'] = 'в', ['5XX'] = 'г', default = 'д' } },
    }))

    t.assert_equals(api.title, 'Магазин')
    t.assert_equals(api.version, '1')
end

g.test_response_entry_is_a_word_a_shape_or_a_table = function()
    t.assert_equals(
        refused_responses({ [200] = 5 }),
        'операция «a».responses[200] — слово, форма либо таблица ответа, а не 5'
    )
    t.assert_equals(
        refused_responses({ [200] = {} }),
        'операция «a».responses[200].description — строка, а не nil'
    )
end

g.test_first_wrong_response_is_named_by_code = function()
    t.assert_equals(
        refused_responses({ default = 5, [500] = 5, [404] = 5 }),
        'операция «a».responses[404] — слово, форма либо таблица ответа, а не 5'
    )
    t.assert_equals(
        refused_responses({ default = 5, ['4XX'] = 5 }),
        'операция «a».responses[4XX] — слово, форма либо таблица ответа, а не 5'
    )
    t.assert_equals(
        refused_responses({ default = 5 }),
        'операция «a».responses[default] — слово, форма либо таблица ответа, а не 5'
    )
end

g.test_media_without_schema_describes_nothing = function()
    t.assert_equals(
        refused_responses({ [200] = { description = 'Текст', media = 'text/plain' } }),
        'операция «a».responses[200]: тип содержимого без схемы — описывать нечего'
    )
end

g.test_two_shapes_under_one_name_are_refused = function()
    local first = helper.data.define({ name = 'Address', fields = { { 'city', 'string' } } })
    local second = helper.data.define({ name = 'Address', fields = { { 'street', 'string' } } })

    t.assert_equals(
        refused({ body = first, responses = { [200] = second } }),
        'две разные формы зовутся Address'
    )
end

g.test_refusal_points_at_the_caller = function()
    local line
    local ok, err = pcall(function()
        line = helper.here() + 1
        openapi.define(helper.spec({}, { titel = 'x' }))
    end)

    t.assert_not(ok)
    t.assert_str_contains(
        tostring(err),
        ('define_test.lua:%d: описание API: ключа «titel»'):format(line)
    )
end

g.test_document_needs_a_router = function()
    local api = openapi.define(helper.spec({}))

    t.assert_equals(helper.thrown(api.document, helper.wrong(5)), 'роутер — таблица, а не число')
    t.assert_equals(
        helper.thrown(api.document, {}),
        'роутер.routes — функция или вызываемая таблица, а не nil'
    )

    local line
    local ok, err = pcall(function()
        line = helper.here() + 1
        api.document({})
    end)

    t.assert_not(ok)
    t.assert_str_contains(tostring(err), ('define_test.lua:%d: роутер.routes'):format(line))
end

g.test_served_checks_its_arguments = function()
    local router = helper.routed(function() end)

    t.assert_equals(helper.thrown(openapi.served, nil, router), 'документ — таблица, а не nil')
    t.assert_equals(
        helper.thrown(openapi.served, {}, router, { selec = 1 }),
        'настройки: ключа «selec» нет, есть select'
    )
    t.assert_equals(
        helper.thrown(openapi.served, {}, helper.wrong('роутер')),
        'роутер — таблица, а не строка'
    )
    t.assert_equals(
        helper.thrown(openapi.served, { paths = 'нет' }, router),
        'документ.paths — таблица, а не строка'
    )
    t.assert_equals(
        helper.thrown(openapi.served, { paths = { ['/a'] = { get = {} }, ['/b'] = box.NULL } }, router),
        'документ.paths[/b] — таблица, а не box.NULL'
    )

    local line
    local ok, err = pcall(function()
        line = helper.here() + 1
        openapi.served({}, {})
    end)

    t.assert_not(ok)
    t.assert_str_contains(tostring(err), ('define_test.lua:%d: роутер.routes'):format(line))

    ok, err = pcall(function()
        line = helper.here() + 1
        openapi.served(helper.wrong(5), router)
    end)

    t.assert_not(ok)
    t.assert_str_contains(tostring(err), ('define_test.lua:%d: документ'):format(line))
end
