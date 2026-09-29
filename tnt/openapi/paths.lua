--- Путь маршрута в описании API: шаблон роутера — пути OpenAPI
--- с параметрами, и начало пути у сервера описания.
---
--- Шаблон разбирает сам роутер (`tnt.router.path`): второй разбор
--- шаблона разошёлся бы с первым при первом новом виде участка.
---
--- Один маршрут бывает несколькими путями. Необязательный участок
--- в конце — это адрес и с ним, и без него (`/a/:x?` отвечает и на `/a`),
--- а хвост `*path` подходит к пустому остатку: раздача `/files` с хвостом
--- отвечает и на сам `/files`. Параметр пути в OpenAPI обязателен всегда,
--- поэтому каждый такой адрес — свой путь описания, от длинного
--- к короткому. Необязательные участки перед хвостом роутер
--- не разворачивает, и описание их не разворачивает тоже: `/files/:dir?`
--- с хвостом за ним на `/files` отвечает 404.
---
--- Пары «косая черта со звёздочкой» в этом файле нет нарочно — ни
--- в комментариях, ни в образцах: мутационный прогон читает её началом
--- блочного комментария и остаток файла не видит.
---
--- Хвост — обычный параметр пути: клиент, который по правилам OpenAPI
--- кодирует косую черту в значении (`a%2Fb`), получает тот же хвост,
--- что и по `a/b`, — роутер раскодирует участки по одному, а хвост
--- склеивает из них.

local route_path = require('tnt.router.path')

local Module = {}

--- Схема значения по ограничению шаблона.
---
--- Образцы роутера — образцы Lua, а `pattern` в OpenAPI — регулярное
--- выражение ECMA: `%a` там ничего не значит. Поэтому образцы записаны
--- здесь заново, знак в знак по смыслу: `%a` роутера — латиница (узел
--- живёт в локали C), `%w` — латиница и цифры.
---@type table<string, table>
Module.SCHEMAS = {
    int = { type = 'integer' },
    uuid = { type = 'string', format = 'uuid' },
    alpha = { type = 'string', pattern = '^[A-Za-z]+$' },
    slug = { type = 'string', pattern = '^[A-Za-z0-9_-]+$' },
}

---@class TntOpenapiVariant
---@field path string Путь описания: `/customers/{id}`
---@field params table[] Параметры пути по порядку участков

--- Схема значения параметра.
---
--- Своя проверка функцией и ограничение группы (`where`) в шаблон
--- не попадают: по объявленному маршруту их не видно, и такой параметр
--- описывается строкой. Незнакомое имя — тоже строкой: роутер мог
--- завести ограничение, которого описание ещё не знает.
---@param segment TntRouterSegment
---@return table
local function schema_of(segment)
    return table.deepcopy(Module.SCHEMAS[segment.constraint] or { type = 'string' })
end

--- Путь описания по первым `count` участкам шаблона.
---
--- Постоянный участок роутер хранит раскодированным и кодирует обратно
--- при сборке адреса; описание пишет его той же записью.
---@param segments TntRouterSegment[]
---@param count integer
---@return TntOpenapiVariant
local function variant(segments, count)
    local pieces, params = {}, {}

    for index = 1, count do
        local segment = segments[index] --[[@as TntRouterSegment]]

        if segment.kind == 'static' then
            table.insert(pieces, route_path.encode(segment.text --[[@as string]], false))
        else
            table.insert(pieces, '{' .. segment.name .. '}')
            table.insert(params, {
                name = segment.name,
                ['in'] = 'path',
                required = true,
                schema = schema_of(segment),
            })
        end
    end

    return { path = '/' .. table.concat(pieces, '/'), params = params }
end

--- Пути описания, которые объявляет шаблон, от длинного к короткому.
---
--- Разворот тот же, что у дерева роутера: необязательные параметры
--- снимаются с конца по одному, а хвост подходит к пустому остатку сам,
--- но необязательных участков перед ним роутер уже не разворачивает.
---@param pattern string Шаблон маршрута целиком, с началом группы
---@return TntOpenapiVariant[]
function Module.variants(pattern)
    local segments = route_path.compile(pattern)
    local found = { variant(segments, #segments) }

    for index = #segments, 1, -1 do
        local segment = segments[index] --[[@as TntRouterSegment]]

        if not segment.optional then
            break
        end

        table.insert(found, variant(segments, index - 1))

        if segment.kind == 'wildcard' then
            break
        end
    end

    return found
end

--- Начало пути у сервера описания и сам сервер без пути.
---
--- Адрес сервера бывает полным (`https://shop.example.org/api/v1`)
--- и относительным (`/api/v1`): путь описания считается от его пути,
--- а косая черта в конце сложилась бы с косой чертой пути в двойную.
--- Смотрится первый сервер: остальные — те же точки входа по другим
--- адресам, а не другое начало пути.
---@param servers table[]|nil
---@return string base Путь сервера без косой черты в конце; пусто — корень
---@return string origin Схема и узел; пусто — у относительного адреса
function Module.base(servers)
    local first = (servers or {})[1] or {}
    local url = tostring(first.url or '')
    local origin = url:match('^%a[%w+.-]*://[^/]*') or ''

    -- Образец совпадает с любой строкой: без косых черт в конце она
    -- вся — захват.
    local base = url:sub(#origin + 1):match('^(.-)[/]*$') --[[@as string]]

    return base, origin
end

--- Путь от начала сервера; nil — путь лежит вне его.
---
--- Начало сравнивается по участкам: `/api/v1` — не начало `/api/v10`.
---@param full string Путь маршрута целиком
---@param base string Путь сервера
---@return string|nil
function Module.relative(full, base)
    if full == base then
        return '/'
    end

    -- Срез от начала — от `-#full`, а не от 1: у единицы мутант `0`
    -- срезает то же самое, и проверкой его не отличить.
    if full:sub(-#full, #base + 1) == base .. '/' then
        return full:sub(#base + 1)
    end

    return nil
end

--- Путь целиком по пути описания и началу его сервера.
---@param base string Путь сервера
---@param path string Путь описания
---@return string
function Module.absolute(base, path)
    if path == '/' and base ~= '' then
        return base
    end

    return base .. path
end

return Module
