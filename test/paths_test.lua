--- Тесты путей описания: шаблон роутера — пути OpenAPI и начало сервера.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.openapi.paths')

local paths = helper.part('tnt.openapi.paths')

--- Параметр пути со схемой.
---@param name string
---@param schema table
---@return table
local function param(name, schema)
    return { name = name, ['in'] = 'path', required = true, schema = schema }
end

--- Строка без ограничения.
local STRING = { type = 'string' }

g.test_constant_path_has_no_parameters = function()
    t.assert_equals(paths.variants('/api/v1/customers'), {
        { path = '/api/v1/customers', params = {} },
    })
end

g.test_root_is_the_slash = function()
    t.assert_equals(paths.variants('/'), { { path = '/', params = {} } })
end

g.test_constraints_become_schemas = function()
    t.assert_equals(paths.variants('/a/:n<int>/:u<uuid>/:w<alpha>/:s<slug>/:x'), {
        {
            path = '/a/{n}/{u}/{w}/{s}/{x}',
            params = {
                param('n', { type = 'integer' }),
                param('u', { type = 'string', format = 'uuid' }),
                param('w', { type = 'string', pattern = '^[A-Za-z]+$' }),
                param('s', { type = 'string', pattern = '^[A-Za-z0-9_-]+$' }),
                param('x', STRING),
            },
        },
    })
end

g.test_every_router_constraint_has_its_schema = function()
    -- Ограничение, которое роутер завёл, а описание не знает, описывалось
    -- бы строкой без границ — и число в пути выглядело бы словом.
    for _, name in ipairs(helper.constraints.names()) do
        t.assert_not_equals(paths.SCHEMAS[name], nil, name)
    end
end

g.test_schema_is_a_copy_for_every_parameter = function()
    local first = paths.variants('/a/:id<int>')[1].params[1]

    first.schema.minimum = 1

    t.assert_equals(paths.variants('/a/:id<int>')[1].params[1].schema, { type = 'integer' })
    t.assert_equals(paths.SCHEMAS.int, { type = 'integer' })
end

g.test_constant_part_keeps_its_encoding = function()
    -- Роутер хранит участок раскодированным: описание пишет его той же
    -- записью, что и сборка адреса по имени.
    t.assert_equals(paths.variants('/v1.0/a%20b/~x')[1].path, '/v1.0/a%20b/~x')
    -- Косая черта внутри участка остаётся закодированной: это один
    -- участок, а не два.
    t.assert_equals(paths.variants('/a%2Fb')[1].path, '/a%2Fb')
end

g.test_trailing_optional_parameters_are_dropped_one_by_one = function()
    t.assert_equals(paths.variants('/a/:x?/:y<int>?'), {
        { path = '/a/{x}/{y}', params = { param('x', STRING), param('y', { type = 'integer' }) } },
        { path = '/a/{x}', params = { param('x', STRING) } },
        { path = '/a', params = {} },
    })
end

g.test_only_optional_tail_is_dropped = function()
    t.assert_equals(paths.variants('/:x?'), {
        { path = '/{x}', params = { param('x', STRING) } },
        { path = '/', params = {} },
    })
end

g.test_tail_also_answers_the_empty_rest = function()
    t.assert_equals(paths.variants('/files/*path'), {
        { path = '/files/{path}', params = { param('path', STRING) } },
        { path = '/files', params = {} },
    })
end

g.test_optional_parameter_before_the_tail_stays = function()
    -- Роутер на `/files` здесь отвечает 404: необязательный участок перед
    -- хвостом он не разворачивает, и описание не обещает лишнего.
    t.assert_equals(paths.variants('/files/:dir?/*path'), {
        { path = '/files/{dir}/{path}', params = { param('dir', STRING), param('path', STRING) } },
        { path = '/files/{dir}', params = { param('dir', STRING) } },
    })
end

g.test_the_router_parses_the_pattern = function()
    t.assert_error_msg_contains(
        'хвост «*path» бывает только последним в «/a/*path/b»',
        function()
            paths.variants('/a/*path/b')
        end
    )
end

g.test_base_of_relative_server = function()
    t.assert_equals({ paths.base({ { url = '/api/v1/' } }) }, { '/api/v1', '' })
end

g.test_base_of_full_server = function()
    t.assert_equals(
        { paths.base({ { url = 'https://shop.example.org:8443/api/v1' }, { url = '/x' } }) },
        { '/api/v1', 'https://shop.example.org:8443' }
    )
    t.assert_equals({ paths.base({ { url = 'http+unix://node' } }) }, { '', 'http+unix://node' })
    t.assert_equals({ paths.base({ { url = 'https://shop.example.org//' } }) }, { '', 'https://shop.example.org' })
    t.assert_equals({ paths.base({ { url = 'h://node/api' } }) }, { '/api', 'h://node' })
    t.assert_equals({ paths.base({ { url = 'file:///srv/' } }) }, { '/srv', 'file://' })
end

g.test_base_without_servers_is_the_root = function()
    t.assert_equals({ paths.base(nil) }, { '', '' })
    t.assert_equals({ paths.base({}) }, { '', '' })
    t.assert_equals({ paths.base({ {} }) }, { '', '' })
    t.assert_equals({ paths.base({ { url = '/' } }) }, { '', '' })
end

g.test_relative_path_starts_at_the_server = function()
    t.assert_equals(paths.relative('/api/v1/customers', '/api/v1'), '/customers')
    t.assert_equals(paths.relative('/api/v1', '/api/v1'), '/')
    t.assert_equals(paths.relative('/customers', ''), '/customers')
    t.assert_equals(paths.relative('/', ''), '/')
end

g.test_path_outside_the_server_has_no_relative = function()
    t.assert_equals(paths.relative('/metrics', '/api/v1'), nil)
    t.assert_equals(paths.relative('/api/v10/x', '/api/v1'), nil)
    t.assert_equals(paths.relative('/api', '/api/v1'), nil)
end

g.test_absolute_path_joins_the_server = function()
    t.assert_equals(paths.absolute('/api/v1', '/customers'), '/api/v1/customers')
    t.assert_equals(paths.absolute('/api/v1', '/'), '/api/v1')
    t.assert_equals(paths.absolute('', '/'), '/')
    t.assert_equals(paths.absolute('', '/x'), '/x')
end
