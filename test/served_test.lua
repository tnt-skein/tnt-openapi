--- Тесты сверки готового документа с маршрутами роутера.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.openapi.served')

local openapi = helper.openapi

--- Операция документа: сверка читает только её место.
local OPERATION = { responses = { ['200'] = { description = 'Да' } } }

--- Документ, написанный руками: пути от сервера, метрики вне его.
---@return table
local function described()
    return {
        openapi = '3.0.3',
        servers = { { url = '/api/v1' } },
        paths = {
            ['/customers'] = { get = OPERATION, post = OPERATION },
            ['/customers/{id}'] = { get = OPERATION },
            ['/metrics'] = { servers = { { url = '/' } }, get = OPERATION },
        },
    }
end

--- Роутер, который обслуживает документ `described`, и страница без имени.
---@return TntRouter
local function panel()
    return helper.routed(function(r)
        r.get('/metrics', helper.handler, { name = 'metrics' })
        r.group('/api/v1', function(api)
            api.get('/customers', helper.handler, { name = 'list' })
            api.post('/customers', helper.handler, { name = 'create' })
            api.get('/customers/:id<int>', helper.handler, { name = 'show' })
        end)
        r.get('/', helper.handler)
    end)
end

g.test_matching_document_is_fine = function()
    t.assert_equals({ openapi.served(described(), panel()) }, { true })
end

g.test_missing_and_extra_operations_are_named = function()
    local document = described()

    document.paths['/customers'].post = nil
    document.paths['/ghost'] = { get = OPERATION, trace = OPERATION }
    document.paths['/customers/{id}'].delete = OPERATION

    t.assert_equals({ openapi.served(document, panel()) }, {
        nil,
        {
            'Операция POST /api/v1/customers обслуживается, но не описана.',
            'Операция DELETE /api/v1/customers/{id} описана, но не обслуживается.',
            'Операция GET /api/v1/ghost описана, но не обслуживается.',
            'Операция TRACE /api/v1/ghost описана, но не обслуживается.',
        },
    })
end

g.test_parameter_name_is_part_of_the_path = function()
    local document = described()

    document.paths['/customers/{uid}'] = document.paths['/customers/{id}']
    document.paths['/customers/{id}'] = nil

    t.assert_equals({ openapi.served(document, panel()) }, {
        nil,
        {
            'Операция GET /api/v1/customers/{id} обслуживается, но не описана.',
            'Операция GET /api/v1/customers/{uid} описана, но не обслуживается.',
        },
    })
end

g.test_path_with_own_full_server_starts_at_its_root = function()
    local document = described()

    document.paths['/metrics'].servers = { { url = 'https://shop.example.org/' } }

    t.assert_equals({ openapi.served(document, panel()) }, { true })
end

g.test_head_is_implied_by_get_only = function()
    local document = described()

    document.paths['/customers/{id}'].head = OPERATION

    t.assert_equals({ openapi.served(document, panel()) }, { true })

    document.paths['/customers'].head = OPERATION

    t.assert_equals({ openapi.served(document, panel()) }, { true })

    local posted = helper.routed(function(r)
        r.post('/a', helper.handler, { name = 'a' })
        r.get('/b', helper.handler, { name = 'b' })
        r.post('/b', helper.handler, { name = 'b.post' })
    end)

    t.assert_equals({
        openapi.served({
            paths = {
                ['/a'] = { post = OPERATION, head = OPERATION },
                ['/b'] = {
                    get = OPERATION,
                    post = OPERATION,
                    head = OPERATION,
                },
            },
        }, posted),
    }, { nil, { 'Операция HEAD /a описана, но не обслуживается.' } })
end

g.test_explicit_head_route_must_be_described = function()
    local router = helper.routed(function(r)
        r.head('/a', helper.handler, { name = 'a' })
    end)

    t.assert_equals({ openapi.served({ paths = { ['/a'] = { get = OPERATION } } }, router) }, {
        nil,
        {
            'Операция HEAD /a обслуживается, но не описана.',
            'Операция GET /a описана, но не обслуживается.',
        },
    })
end

g.test_every_path_of_a_route_is_served = function()
    local router = helper.routed(function(r)
        r.get('/files/*path', helper.handler, { name = 'files' })
        r.get('/a/:x?', helper.handler, { name = 'a' })
    end)

    t.assert_equals({
        openapi.served({
            paths = {
                ['/files/{path}'] = { get = OPERATION },
                ['/files'] = { get = OPERATION },
                ['/a/{x}'] = { get = OPERATION },
                ['/a'] = { get = OPERATION },
            },
        }, router),
    }, { true })
    t.assert_equals({ openapi.served({ paths = { ['/files/{path}'] = { get = OPERATION } } }, router) }, {
        nil,
        -- По порядку маршрутов, а он у роутера — по шаблону.
        {
            'Операция GET /a/{x} обслуживается, но не описана.',
            'Операция GET /a обслуживается, но не описана.',
            'Операция GET /files обслуживается, но не описана.',
        },
    })
end

g.test_one_operation_of_two_routes_is_named_once = function()
    local router = helper.routed(function(r)
        r.get('/a/:id<int>', helper.handler, { name = 'by_number' })
        r.get('/a/:id<uuid>', helper.handler, { name = 'by_uuid' })
    end)

    t.assert_equals({ openapi.served({}, router) }, {
        nil,
        { 'Операция GET /a/{id} обслуживается, но не описана.' },
    })
end

g.test_route_on_any_method_cannot_be_checked = function()
    local router = helper.routed(function(r)
        r.any('/hook', helper.handler, { name = 'hook' })
    end)

    t.assert_equals({ openapi.served({ paths = { ['/hook'] = { post = OPERATION } } }, router) }, {
        nil,
        {
            'Маршрут ANY /hook объявлен на любой способ: сверять нечего.',
            'Операция POST /hook описана, но не обслуживается.',
        },
    })
end

g.test_selection_decides_what_the_api_is = function()
    local router = helper.routed(function(r)
        r.get('/api/a', helper.handler)
        r.get('/page', helper.handler, { name = 'page' })
        r.any('/hook', helper.handler)
    end)
    local document = { paths = { ['/api/a'] = { get = OPERATION } } }

    t.assert_equals({
        openapi.served(document, router, {
            select = function(route)
                return route.pattern:find('^/api/') ~= nil
            end,
        }),
    }, { true })
    t.assert_equals({ openapi.served(document, router) }, {
        nil,
        {
            'Операция GET /page обслуживается, но не описана.',
            'Операция GET /api/a описана, но не обслуживается.',
        },
    })
end

g.test_generated_document_passes_its_own_check = function()
    local router = panel()
    local api = openapi.define(helper.spec({
        list = { responses = { [200] = 'Да' } },
        create = { responses = { [201] = 'Заведён' } },
        show = { responses = { [200] = 'Да' } },
        metrics = { responses = { [200] = 'Числа' } },
    }, { servers = { { url = '/api/v1' } } }))

    t.assert_equals({
        openapi.served(api.document(router) --[[@as table]], router),
    }, { true })
end
