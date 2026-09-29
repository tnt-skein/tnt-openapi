--- Общие средства проверок описания API.
---
--- Документ и отказы сравниваются целиком и дословно: документ уходит
--- клиентам API, а отказ — тому, кто объявил описание, и «где-то там
--- сказано про маршрут» их не проверяет.
---
--- Роутер в проверках настоящий, а не список маршрутов, написанный
--- руками: иначе проверки судили бы договор описания с самим собой,
--- а не с тем, что роутер отдаёт на самом деле.
---
--- Исходники пакета читаются с диска, а не через `require`: у Tarantool
--- свой загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему. Поэтому
--- файлы читаются сами, в порядке зависимостей, и кладутся
--- в `package.loaded` под именами модулей: `require` изнутри пакета
--- находит их первыми. Зависимости — `tnt-router`, `tnt-data`
--- и `tnt-must` — и объявленный запрос `tnt-query` стоят в `.rocks`,
--- и пакет берёт их обычным `require`: проверяется этот пакет, а не они.
---
--- Проверки берут всё через этот помощник: он — единственное, чем файл
--- проверок отличается от того же файла там, где пакет живёт рядом
--- со своими зависимостями.

local fio = require('fio')

--- Модули пакета в порядке зависимостей.
local MODULES = {
    { name = 'tnt.openapi.paths', path = 'tnt/openapi/paths.lua' },
    { name = 'tnt.openapi.operation', path = 'tnt/openapi/operation.lua' },
    { name = 'tnt.openapi.declare', path = 'tnt/openapi/declare.lua' },
    { name = 'tnt.openapi.document', path = 'tnt/openapi/document.lua' },
    { name = 'tnt.openapi.served', path = 'tnt/openapi/served.lua' },
    { name = 'tnt.openapi', path = 'tnt/openapi.lua' },
}

--- Части пакета: имя модуля → его таблица.
---
--- Собираются при загрузке этого помощника, то есть по разу на каждый файл
--- проверок, который его берёт: своего состояния у пакета нет — ни
--- настроек, ни подменяемых средств.
---@type table<string, any>
local PARTS = {}

for _, module in ipairs(MODULES) do
    local chunk, failure = loadfile(fio.abspath(module.path))

    if chunk == nil then
        error(('исходник %s не читается: %s'):format(module.name, tostring(failure)))
    end

    local value = chunk()

    -- Пустое значение в `package.loaded` для `require` значит «не загружен»,
    -- и следующий модуль списка молча взял бы установленную копию из `.rocks`.
    if value == nil then
        error(('исходник %s не вернул модуль'):format(module.name))
    end

    package.loaded[module.name] = value
    PARTS[module.name] = value
end

local helper = {}

--- Фасад пакета, собранный из исходников.
helper.openapi = PARTS['tnt.openapi']

--- Соседи — те же установленные копии, которые берёт пакет.
helper.router = require('tnt.router')
helper.data = require('tnt.data')
helper.query = require('tnt.query')

--- Ограничения шаблона, которые знает роутер.
helper.constraints = require('tnt.router.constraints')

--- Отдельный модуль пакета.
---@param name string Имя модуля: `tnt.openapi.paths`
---@return any
function helper.part(name)
    return PARTS[name]
end

--- Негодный аргумент — нарочно.
---
--- Проверки отказов передают то, чего договор не допускает. Анализатор
--- типов о таком намерении знать не может и справедливо ругается
--- на каждую такую строку.
---@param value any
---@return any
function helper.wrong(value)
    return value
end

--- Номер строки, с которой позвали эту функцию: так проверки узнают
--- строку, на которую обязан указать отказ.
---@return integer
function helper.here()
    return (debug.getinfo(2, 'l') --[[@as { currentline: integer }]]).currentline
end

--- Объявляет формы группы перед её проверками.
---
--- Не при загрузке файла: мутант, сломавший объявление, иначе ронял бы
--- загрузку, и гейт мутаций не отличил бы его от проверок, которые
--- не запустились вовсе.
---@param g table Группа luatest
---@param declare fun()
function helper.declare(g, declare)
    g.before_all(declare)
end

--- Текст исключения, брошенного вызовом, без места впереди.
---
--- `pcall` зовёт функцию сам, и `error(msg, 2)` упирается в его кадр C:
--- места в сообщении нет. Что место есть при вызове из кода на Lua,
--- проверяется отдельно и нарочно.
---@param call function
---@param ... any
---@return string
function helper.thrown(call, ...)
    local ok, err = pcall(call, ...)

    assert(not ok, 'вызов не бросил исключения')

    return (tostring(err):gsub('^[^:]+:%d+: ', ''))
end

--- Ключи таблицы списком.
---@param map table
---@return any[]
function helper.keys(map)
    local keys = {}

    for key in pairs(map) do
        table.insert(keys, key)
    end

    return keys
end

--- Роутер с маршрутами, объявленными функцией.
---@param declare fun(router: TntRouter)
---@return TntRouter
function helper.routed(declare)
    local router = helper.router.new()

    declare(router)

    return router
end

--- Обработчик, который ни разу не зовут: документ строится по объявлению.
---@return table
function helper.handler()
    return helper.router.no_content()
end

--- Описание с обязательными словами и названными операциями.
---@param operations table<string, table>
---@param extra table|nil Прочие настройки описания
---@return table
function helper.spec(operations, extra)
    local spec = { title = 'Магазин', version = '1', operations = operations }

    for key, value in pairs(extra or {}) do
        spec[key] = value
    end

    return spec
end

return helper
