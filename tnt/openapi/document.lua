--- Документ описания API: объявленные маршруты с их описаниями.
---
--- Пути, способы и параметры пути берутся у роутера, слова, тела
--- и ответы — у описания, схемы — у форм. Описание ищется по имени
--- маршрута: имя переживает перенос группы под другое начало пути,
--- а шаблон — нет.
---
--- Документ собирается только целиком согласным. Маршрут API без описания,
--- описание без маршрута, параметр, которого нет в пути, — отказ парой
--- `nil, problems` со всеми расхождениями сразу: документ, где часть
--- маршрутов молча пропала, выглядит полным и врёт клиенту.

local operation = require('tnt.openapi.operation')
local paths = require('tnt.openapi.paths')

local Module = {}

--- Версия OpenAPI, которой пишется документ.
---
--- 3.0, а не 3.1: схемы форм (`nullable`, `writeOnly`) написаны по 3.0,
--- а в 3.1 `nullable` уже нет.
Module.VERSION = '3.0.3'

--- Как маршрут назван в отказе: имя, способ и шаблон.
---@param route TntOpenapiRoute
---@return string
local function shown(route)
    local where = ('%s %s'):format(route.method, route.pattern)

    if route.name == nil then
        return where
    end

    return ('%s (%s)'):format(route.name, where)
end

--- Сборка документа: найденные пути и расхождения.
---@class TntOpenapiAssembly
---@field api TntOpenapiApi
---@field base string Путь сервера описания
---@field origin string Схема и узел сервера
---@field paths table<string, table> Пути описания
---@field owners table<string, TntOpenapiRoute> Какой маршрут дал операцию: «способ путь» → маршрут
---@field problems string[]

--- Записывает расхождение.
---@param assembly TntOpenapiAssembly
---@param template string
---@param ... any
local function say(assembly, template, ...)
    table.insert(assembly.problems, template:format(...))
end

--- Параметры пути, которых описание называет, а у маршрута их нет.
---@param prepared TntOpenapiPrepared
---@param variant TntOpenapiVariant Самый длинный путь маршрута
---@return string[]
local function strangers(prepared, variant)
    local known, found = {}, {}

    for _, parameter in ipairs(variant.params) do
        known[parameter.name] = true
    end

    for name in pairs(prepared.about) do
        if not known[name] then
            table.insert(found, name)
        end
    end

    table.sort(found)

    return found
end

--- Кладёт операцию маршрута на все его пути.
---
--- Путь вне начала сервера пишется целиком и со своим сервером — корнем
--- того же узла: иначе клиент приложил бы к нему начало сервера и ушёл
--- по адресу, которого нет.
---@param assembly TntOpenapiAssembly
---@param route TntOpenapiRoute
---@param prepared TntOpenapiPrepared
local function place(assembly, route, prepared)
    if route.method == 'ANY' then
        return say(
            assembly,
            'Маршрут %s объявлен на любой способ: описанию нужен способ.',
            shown(route)
        )
    end

    local variants = paths.variants(route.pattern)

    for _, name in
        ipairs(strangers(prepared, variants[1] --[[@as TntOpenapiVariant]]))
    do
        say(assembly, 'Описание %s: у маршрута нет параметра %s.', route.name, name)
    end

    local method = route.method:lower()

    for index, variant in ipairs(variants) do
        local relative = paths.relative(variant.path, assembly.base)
        local key = relative or variant.path
        local item = assembly.paths[key] or {}
        local owner = assembly.owners[method .. ' ' .. variant.path]

        if relative == nil then
            item.servers = { { url = assembly.origin .. '/' } }
        end

        if owner ~= nil then
            say(
                assembly,
                'Маршруты %s и %s дают одну операцию %s %s.',
                shown(owner),
                shown(route),
                route.method,
                variant.path
            )
        else
            -- Опознаватель — у самого длинного пути: в документе он обязан
            -- быть единственным, а короткие пути — тот же маршрут.
            item[method] = operation.instantiate(prepared, variant, index == 1 and route.name or nil)
            assembly.owners[method .. ' ' .. variant.path] = route
        end

        assembly.paths[key] = item
    end
end

--- Собирает документ по маршрутам роутера.
---@param api TntOpenapiApi
---@param routes TntOpenapiRoute[]
---@return table|nil document
---@return string[]|nil problems
function Module.build(api, routes)
    local base, origin = paths.base(api.servers)

    ---@type TntOpenapiAssembly
    local assembly = { api = api, base = base, origin = origin, paths = {}, owners = {}, problems = {} }
    local seen = {}

    for _, route in ipairs(routes) do
        local prepared = api.operations[route.name or '']

        if prepared ~= nil then
            seen[route.name] = true

            place(assembly, route, prepared)
        elseif api.select(route) then
            if route.name == nil then
                say(
                    assembly,
                    'Маршрут %s без имени: описание ищется по имени.',
                    shown(route)
                )
            else
                say(assembly, 'Маршрут %s не описан.', shown(route))
            end
        end
    end

    local names = {}

    for name in pairs(api.operations) do
        table.insert(names, name)
    end

    table.sort(names)

    for _, name in ipairs(names) do
        if not seen[name] then
            say(assembly, 'Описание %s: маршрута с таким именем нет.', name)
        end
    end

    if assembly.problems[1] ~= nil then
        return nil, assembly.problems
    end

    local components = {
        schemas = next(api.schemas) ~= nil and table.deepcopy(api.schemas) or nil,
        securitySchemes = table.deepcopy(api.schemes --[[@as table]]),
    }

    return {
        openapi = Module.VERSION,
        info = { title = api.title, version = api.version, description = api.description },
        servers = table.deepcopy(api.servers --[[@as table]]),
        security = table.deepcopy(api.security --[[@as table]]),
        -- Пометка словаря: без маршрутов пустая таблица уехала бы в JSON
        -- списком `[]`, а `paths` в OpenAPI — объект. `mapping`, а не `map`:
        -- с `map` YAML пишет все пути одной строкой в фигурных скобках.
        paths = setmetatable(assembly.paths, { __serialize = 'mapping' }),
        components = next(components) ~= nil and components or nil,
    }
end

return Module
