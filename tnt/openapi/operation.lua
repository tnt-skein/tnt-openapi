--- Операция описания по объявлению: ответы, тело запроса, параметры.
---
--- Форма `tnt-data` на месте схемы становится ссылкой
--- `#/components/schemas/<имя>`, а сама форма уходит в список, из которого
--- объявление соберёт `components.schemas`, — и в теле запроса, и в ответе,
--- и глубоко внутри своей схемы (`{ type = 'array', items = User }`).
--- Второй схемы рядом с формой не пишут: она разошлась бы с проверкой
--- молча.
---
--- Операция собирается при объявлении один раз, а по маршруту к ней
--- дописываются только параметры пути и опознаватель: ответы и тело
--- от адреса не зависят.

local data = require('tnt.data')

local Module = {}

--- Где лежат схемы форм в документе.
Module.REF = '#/components/schemas/'

--- Тип содержимого, если его не назвали.
Module.JSON = 'application/json'

--- Слово ответа `default`, если его не назвали.
---
--- `default` есть у каждой операции: упавший обработчик отвечает 500
--- на любом адресе, и описание без этого ответа обещало бы, что отказов,
--- кроме названных, не бывает.
Module.DEFAULT = 'Отказ, не названный у операции'

---@class TntOpenapiRefusal
---@field description string Слово ответа `default`
---@field content table Тело отказа по типу содержимого

---@class TntOpenapiPrepared
---@field operation table Операция без параметров пути и опознавателя
---@field about table<string, string> Слова параметров пути по именам

--- Копия значения, в которой формы заменены ссылками.
---
--- Разметка таблицы (`__serialize`) остаётся: пустой словарь без неё
--- уехал бы в JSON списком `[]`.
---@param value any
---@param shapes TntDataShape<any>[] Сюда складываются встреченные формы
---@return any
function Module.referenced(value, shapes)
    if data.is(value) then
        table.insert(shapes, value)

        return { ['$ref'] = Module.REF .. value.name }
    end

    if type(value) ~= 'table' then
        return value
    end

    local copy = {}

    for key, item in pairs(value) do
        copy[key] = Module.referenced(item, shapes)
    end

    return setmetatable(copy, getmetatable(value))
end

--- Тело по типу содержимого.
---@param schema table Форма либо схема
---@param media string|nil
---@param shapes TntDataShape<any>[]
---@return table
local function content(schema, media, shapes)
    return { [media or Module.JSON] = { schema = Module.referenced(schema, shapes) } }
end

--- Ответ ли это отказа: код 4xx, 5xx — и числом, и диапазоном `4XX` —
--- или `default`.
---@param code string
---@return boolean
local function refusing(code)
    return code == 'default' or code:find('^[45]') ~= nil
end

--- Ответ по записи объявления.
---
--- Отказ, описанный одним словом, получает тело отказа описания:
--- тело у отказа одно на всё приложение, и повторять его у каждого
--- кода незачем.
---@param code string
---@param entry string|table Слово, форма либо таблица ответа
---@param refusal TntOpenapiRefusal|nil
---@param shapes TntDataShape<any>[]
---@return table
local function response(code, entry, refusal, shapes)
    local answer

    if type(entry) == 'string' then
        answer = { description = entry }
    elseif data.is(entry) then
        answer = { description = entry.about or entry.name, content = content(entry, nil, shapes) }
    else
        answer = { description = entry.description }

        if entry.schema ~= nil then
            answer.content = content(entry.schema, entry.media, shapes)
        end
    end

    if answer.content == nil and refusal ~= nil and refusing(code) then
        answer.content = table.deepcopy(refusal.content)
    end

    return answer
end

--- Тело отказа описания.
---@param entry table Форма либо таблица `{ schema, media, description }`
---@param shapes TntDataShape<any>[]
---@return TntOpenapiRefusal
function Module.refusal(entry, shapes)
    if data.is(entry) then
        entry = { schema = entry }
    end

    return {
        description = entry.description or Module.DEFAULT,
        content = content(entry.schema, entry.media, shapes),
    }
end

--- Тело запроса.
---@param entry table Форма либо таблица `{ schema, media, description, optional }`
---@param shapes TntDataShape<any>[]
---@return table
local function body(entry, shapes)
    if data.is(entry) then
        entry = { schema = entry }
    end

    return {
        description = entry.description,
        required = not entry.optional,
        content = content(entry.schema, entry.media, shapes),
    }
end

--- Собирает операцию по проверенному объявлению.
---@param spec table Объявление операции
---@param refusal TntOpenapiRefusal|nil
---@param shapes TntDataShape<any>[]
---@return TntOpenapiPrepared
function Module.prepare(spec, refusal, shapes)
    local responses = {}

    for code, entry in pairs(spec.responses) do
        local key = tostring(code)

        responses[key] = response(key, entry, refusal, shapes)
    end

    if responses.default == nil then
        responses.default = response('default', (refusal or {}).description or Module.DEFAULT, refusal, shapes)
    end

    -- Параметры строки запроса — из объявления запроса: имена белого списка
    -- и схемы значений у него те же, что у разбора.
    local parameters = spec.query ~= nil and spec.query.parameters() or {}

    for _, parameter in ipairs(spec.parameters or {}) do
        table.insert(parameters, Module.referenced(parameter, shapes))
    end

    local operation = {
        summary = spec.summary,
        description = spec.description,
        tags = table.deepcopy(spec.tags),
        deprecated = spec.deprecated,
        security = table.deepcopy(spec.security),
        parameters = parameters,
        responses = responses,
    }

    if spec.body ~= nil then
        operation.requestBody = body(spec.body, shapes)
    end

    return { operation = operation, about = spec.params or {} }
end

--- Операция на одном пути маршрута.
---
--- Параметры пути идут первыми, по порядку участков, за ними — строки
--- запроса и названные руками. Пустой список не пишется: OpenAPI его
--- допускает, но читать в описании пустое место незачем.
---@param prepared TntOpenapiPrepared
---@param variant TntOpenapiVariant
---@param id string|nil Опознаватель операции; nil — не писать
---@return table
function Module.instantiate(prepared, variant, id)
    local operation = table.deepcopy(prepared.operation) --[[@as table]]
    local parameters = {}

    for _, parameter in ipairs(variant.params) do
        local copy = table.deepcopy(parameter)

        copy.description = prepared.about[parameter.name]

        table.insert(parameters, copy)
    end

    for _, parameter in
        ipairs(operation.parameters --[[@as table[] ]])
    do
        table.insert(parameters, parameter)
    end

    operation.operationId = id
    operation.parameters = parameters[1] ~= nil and parameters or nil

    return operation
end

return Module
