--- Объявление описания API: проверка при загрузке и сборка операций.
---
--- Ошибка в объявлении — ошибка программиста: отсюда она уходит текстом,
--- а бросает её фасад строкой того, кто объявлял описание. Проверяется
--- всё, что можно проверить без роутера: настройки, операции, коды
--- и записи ответов, формы. Что операция называет существующий маршрут
--- и его параметры, видно только по роутеру — это сверит `document`.

local explain = require('tnt.must').explain
local show = require('tnt.must.fail').show

local data = require('tnt.data')

local operation = require('tnt.openapi.operation')

local Module = {}

--- Настройки описания.
local SPEC = {
    title = 'not_empty',
    version = 'not_empty',
    description = '?string',
    servers = { '?array_of', 'options', { url = 'not_empty', description = '?string' } },
    select = '?callable',
    refusal = '?table',
    security = '?array',
    security_schemes = '?table',
    operations = 'table',
}

--- Настройки операции.
local OPERATION = {
    summary = '?string',
    description = '?string',
    tags = { '?array_of', 'string' },
    deprecated = '?boolean',
    security = '?array',
    params = '?table',
    query = '?table',
    parameters = { '?array_of', 'table' },
    body = '?table',
    responses = 'table',
}

--- Тело запроса таблицей: у формы довесков нет.
local BODY = { schema = 'table', media = '?not_empty', description = '?string', optional = '?boolean' }

--- Ответ таблицей.
local RESPONSE = { description = 'string', schema = '?table', media = '?not_empty' }

--- Тело отказа таблицей.
local REFUSAL = { schema = 'table', media = '?not_empty', description = '?string' }

---@class TntOpenapiRoute Маршрут, как его отдаёт `routes()` роутера
---@field method string Способ заглавными; `ANY` — любой
---@field pattern string Шаблон целиком, с началом группы
---@field name string|nil Имя маршрута

---@class TntOpenapiApi
---@field title string
---@field version string
---@field description string|nil
---@field servers table[]|nil
---@field security table[]|nil
---@field schemes table|nil Схемы входа для `components.securitySchemes`
---@field select fun(route: TntOpenapiRoute): boolean Какие маршруты обязаны быть описаны
---@field operations table<string, TntOpenapiPrepared> Операции по именам маршрутов
---@field schemas table<string, table> Схемы форм для `components.schemas`

--- Какие маршруты составляют API, если не сказано иное: именованные.
---
--- Имя — договор с клиентом API: по нему строится адрес и находится
--- описание, а страницы и раздача файлов открываются ссылкой.
---@param route TntOpenapiRoute
---@return boolean
function Module.named(route)
    return route.name ~= nil
end

--- Отказ о записи «форма либо таблица»; nil — запись годная.
---@param value table
---@param place string
---@param spec table Настройки таблицы
---@return string|nil
local function refused_entry(value, place, spec)
    if data.is(value) then
        return nil
    end

    return explain.options(value, place, spec)
end

--- Годный ли код ответа: целое от 100 до 599, `default` либо `4XX`.
---@param code any
---@return boolean
local function valid_code(code)
    if type(code) == 'number' then
        return code == math.floor(code) and code >= 100 and code <= 599
    end

    return code == 'default' or tostring(code):find('^[1-5]XX$') ~= nil
end

--- Отказ об ответах операции; nil — ответы годные.
---@param responses table
---@param place string
---@return string|nil
local function refused_responses(responses, place)
    if next(responses) == nil then
        return place .. '.responses — хотя бы один ответ, а не пустая таблица'
    end

    local codes = {}

    for code in pairs(responses) do
        if not valid_code(code) then
            return ('%s.responses: код ответа — целое от 100 до 599, «default» либо «4XX», а не %s'):format(
                place,
                show(code)
            )
        end

        table.insert(codes, tostring(code))
    end

    table.sort(codes)

    for _, code in ipairs(codes) do
        local entry = responses[tonumber(code) or code]
        local where = ('%s.responses[%s]'):format(place, code)
        local complaint

        if type(entry) == 'table' then
            complaint = refused_entry(entry, where, RESPONSE)

            if complaint == nil and entry.media ~= nil and entry.schema == nil then
                complaint = where
                    .. ': тип содержимого без схемы — описывать нечего'
            end
        elseif type(entry) ~= 'string' then
            complaint = ('%s — слово, форма либо таблица ответа, а не %s'):format(
                where,
                show(entry)
            )
        end

        if complaint ~= nil then
            return complaint
        end
    end

    return nil
end

--- Отказ об операции; nil — операция годная.
---@param entry any
---@param place string
---@return string|nil
local function refused_operation(entry, place)
    local complaint = explain.options(entry, place, OPERATION)

    if complaint ~= nil then
        return complaint
    end

    for name, about in pairs(entry.params or {}) do
        complaint = complaint or explain.kind(about, ('%s.params.%s'):format(place, tostring(name)), 'string')
    end

    if complaint == nil and entry.query ~= nil then
        complaint = explain.kind(entry.query.parameters, place .. '.query.parameters', 'callable')
    end

    if complaint == nil and entry.body ~= nil then
        complaint = refused_entry(entry.body, place .. '.body', BODY)
    end

    return complaint or refused_responses(entry.responses, place)
end

--- Отказ об операциях; nil — все годные.
---
--- Операции проверяются по порядку имён: из двух негодных называется
--- всегда одна и та же.
---@param operations table
---@return string[]|nil names Имена по порядку
---@return string|nil complaint
local function checked_operations(operations)
    local names = {}

    for name in pairs(operations) do
        if type(name) ~= 'string' or name == '' then
            return nil,
                ('описание API.operations: имя маршрута — непустая строка, а не %s'):format(
                    show(name)
                )
        end

        table.insert(names, name)
    end

    table.sort(names)

    for _, name in ipairs(names) do
        local complaint = refused_operation(operations[name], ('операция «%s»'):format(name))

        if complaint ~= nil then
            return nil, complaint
        end
    end

    return names
end

--- Собирает описание по объявлению.
---@param spec any
---@return TntOpenapiApi|nil api
---@return string|nil complaint
function Module.define(spec)
    local complaint = explain.options(spec, 'описание API', SPEC)

    if complaint == nil and spec.refusal ~= nil then
        complaint = refused_entry(spec.refusal, 'описание API.refusal', REFUSAL)
    end

    if complaint ~= nil then
        return nil, complaint
    end

    local names, wrong = checked_operations(spec.operations)

    if names == nil then
        return nil, wrong
    end

    local shapes = {}
    local refusal = spec.refusal ~= nil and operation.refusal(spec.refusal, shapes) or nil
    local operations = {}

    for _, name in ipairs(names) do
        operations[name] = operation.prepare(spec.operations[name], refusal, shapes)
    end

    -- Две разные формы под одним именем — ошибка программиста, и видна
    -- она только на всём списке форм. Сборщик схем бросает; бросок
    -- превращается в текст, чтобы место у него было одно — строка того,
    -- кто объявлял описание.
    local collected, schemas = pcall(data.components, shapes)

    if not collected then
        return nil, tostring(schemas)
    end

    return {
        title = spec.title,
        version = spec.version,
        description = spec.description,
        servers = table.deepcopy(spec.servers),
        security = table.deepcopy(spec.security),
        schemes = table.deepcopy(spec.security_schemes),
        select = spec.select or Module.named,
        operations = operations,
        schemas = schemas,
    }
end

return Module
