--- Описание API из объявленных маршрутов роутера и форм `tnt-data`.
---
--- Описание, которое пишут рядом с кодом руками, расходится с ним молча:
--- маршрут появился и не описан, поле переименовали в форме и забыли
--- в документе. Здесь документ OpenAPI 3.0 — следствие объявлений: пути,
--- способы и параметры пути даёт роутер, схемы — формы, параметры строки
--- запроса — объявленный запрос, а руками пишутся только слова:
---
---     local openapi = require('tnt.openapi')
---
---     local Api = openapi.define({
---         title = 'Магазин',
---         version = '1',
---         servers = { { url = '/api/v1' } },
---         refusal = { schema = Problem, media = 'application/problem+json' },
---         operations = {
---             ['customers.list'] = { summary = 'Клиенты', query = Customers, responses = { [200] = CustomerPage } },
---             ['customers.show'] = {
---                 summary = 'Клиент по номеру',
---                 params = { id = 'Номер клиента' },
---                 responses = { [200] = Customer, [404] = 'Клиента нет' },
---             },
---             ['customers.create'] = {
---                 summary = 'Завести клиента',
---                 body = NewCustomer,
---                 responses = { [201] = Customer, [422] = 'Поля не прошли проверку' },
---             },
---         },
---     })
---
---     local document, problems = Api.document(router)   -- таблица OpenAPI либо расхождения
---     router.get('/openapi.json', function() return router.json(document) end)
---
---     local ok, drift = openapi.served(yaml.decode(text), router)   -- документ руками против маршрутов
---
--- Описание операции ищется по имени маршрута. Какие маршруты составляют
--- API, говорит `select`; по умолчанию — все именованные. Маршрут API без
--- описания, описание без маршрута и параметр, которого в пути нет, —
--- отказ `document` парой `nil, problems` со всеми расхождениями сразу:
--- неполный документ выглядел бы полным.
---
--- Исключение — ошибка программиста: негодное объявление, две разные
--- формы под одним именем, роутер без `routes`. Отказ указывает на строку
--- вызывающего.
---
--- Настроек и состояния у пакета нет — ни `configure`, ни `new`,
--- ни `default`, ни `status`: описание — значение, собранное объявлением.
--- Подробно — `docs/openapi.md`.

local must = require('tnt.must')

local declare = require('tnt.openapi.declare')
local document = require('tnt.openapi.document')
local served = require('tnt.openapi.served')

local Module = {}

--- Версия OpenAPI, которой пишется документ.
Module.VERSION = document.VERSION

--- Настройки сверки готового документа.
local SERVED = { select = '?callable' }

---@class TntOpenapi
---@field title string Название API
---@field version string Версия API
---@field document fun(router: table): table|nil, string[]|nil Документ OpenAPI либо расхождения

---@class TntOpenapiServedOptions
---@field select (fun(route: TntOpenapiRoute): boolean)|nil Какие маршруты составляют API; по умолчанию — именованные

--- Маршруты роутера; негодный роутер — исключение на строке того,
--- кто позвал фасад.
---@param router any
---@return TntOpenapiRoute[]
local function routes_of(router)
    local check = must.at(3)

    check.table(router, 'роутер')
    check.callable(router.routes, 'роутер.routes')

    return router.routes()
end

--- Объявляет описание API.
---@param spec table title, version, description, servers, select, refusal, security, security_schemes, operations
---@return TntOpenapi
function Module.define(spec)
    local api, complaint = declare.define(spec)

    if api == nil then
        error(complaint, 2)
    end

    local described = {
        title = api.title,
        version = api.version,
    }

    function described.document(router)
        return document.build(api --[[@as TntOpenapiApi]], routes_of(router))
    end

    return described --[[@as TntOpenapi]]
end

--- Сверяет готовый документ с маршрутами роутера: каждая операция API
--- описана, и каждая описанная обслуживается.
---@param spec table Документ OpenAPI: таблица, как её отдаёт разбор YAML или JSON
---@param router table Роутер `tnt-router` либо что угодно с `routes()`
---@param opts TntOpenapiServedOptions|nil
---@return true|nil ok
---@return string[]|nil problems
function Module.served(spec, router, opts)
    local check = must.at(2)

    check.table(spec, 'документ')
    check.optional.options(opts, 'настройки', SERVED)

    -- Путь, записанный не таблицей, — сломанный документ, а не расхождение
    -- с кодом: сверять в нём нечего, и сказать об этом надо его месту.
    for path, item in pairs(check.optional.table(spec.paths, 'документ.paths') or {}) do
        check.table(item, ('документ.paths[%s]'):format(path))
    end

    return served.check(spec, routes_of(router), (opts or {}).select or declare.named)
end

return Module
