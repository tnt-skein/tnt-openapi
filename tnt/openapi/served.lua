--- Сверка готового документа с маршрутами: описано ли то, что
--- обслуживается, и обслуживается ли то, что описано.
---
--- Документ, написанный руками, расходится с кодом молча: маршрут
--- появился и не описан — чужой клиент узнает о нём, когда сломается;
--- описан, но исчез — вводит в заблуждение того, кто читает описание.
--- Сверка идёт по операции — способу и пути целиком, от начала сервера,
--- — а не по одному пути: способ, добавленный к описанному пути,
--- сверка пути не заметила бы.
---
--- Слов, тел и ответов сверка не читает: их по маршруту не видно.

local paths = require('tnt.openapi.paths')

local Module = {}

--- Способы, которые OpenAPI держит в описании пути.
local METHODS = { 'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace' }

--- Операции документа: «СПОСОБ путь» → true.
---
--- Путь считается от своего сервера, если он у пути есть, иначе
--- от сервера документа: выкладка метрик живёт вне начала API.
---@param document table
---@return table<string, boolean>
local function described(document)
    local found = {}
    local base = paths.base(document.servers)

    for path, item in pairs(document.paths or {}) do
        local own = item.servers ~= nil and paths.base(item.servers) or base
        local full = paths.absolute(own, path)

        for _, method in ipairs(METHODS) do
            if item[method] ~= nil then
                found[method:upper() .. ' ' .. full] = true
            end
        end
    end

    return found
end

---@class TntOpenapiServing Что обслуживают маршруты API
---@field order string[] Операции по порядку маршрутов, без повторов
---@field served table<string, boolean> Операции, которые обязаны быть описаны
---@field implied table<string, boolean> HEAD у путей с GET: описывать можно, но не обязательно

--- Операции маршрутов API.
---
--- HEAD роутер обслуживает сам тем же обработчиком, что GET: описанный
--- HEAD у пути с GET обслуживается, а описывать его у каждого GET
--- не нужно.
---@param routes TntOpenapiRoute[]
---@param select fun(route: TntOpenapiRoute): boolean
---@param problems string[] Сюда дописываются маршруты, которые сверить нечем
---@return TntOpenapiServing
local function serving(routes, select, problems)
    local result = { order = {}, served = {}, implied = {} }

    for _, route in ipairs(routes) do
        local chosen = select(route)

        if chosen and route.method == 'ANY' then
            table.insert(
                problems,
                ('Маршрут ANY %s объявлен на любой способ: сверять нечего.'):format(
                    route.pattern
                )
            )
        elseif chosen then
            for _, variant in ipairs(paths.variants(route.pattern)) do
                local key = route.method .. ' ' .. variant.path

                if not result.served[key] then
                    table.insert(result.order, key)
                end

                result.served[key] = true

                if route.method == 'GET' then
                    result.implied['HEAD ' .. variant.path] = true
                end
            end
        end
    end

    return result
end

--- Сверяет документ с маршрутами.
---@param document table
---@param routes TntOpenapiRoute[]
---@param select fun(route: TntOpenapiRoute): boolean Какие маршруты составляют API
---@return true|nil ok
---@return string[]|nil problems
function Module.check(document, routes, select)
    local problems = {}
    local documented = described(document)
    local routed = serving(routes, select, problems)

    for _, key in ipairs(routed.order) do
        if not documented[key] then
            table.insert(
                problems,
                ('Операция %s обслуживается, но не описана.'):format(key)
            )
        end
    end

    local keys = {}

    for key in pairs(documented) do
        table.insert(keys, key)
    end

    table.sort(keys)

    for _, key in ipairs(keys) do
        if not routed.served[key] and not routed.implied[key] then
            table.insert(
                problems,
                ('Операция %s описана, но не обслуживается.'):format(key)
            )
        end
    end

    if problems[1] ~= nil then
        return nil, problems
    end

    return true
end

return Module
