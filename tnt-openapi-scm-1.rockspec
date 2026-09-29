rockspec_format = '3.0'

package = 'tnt-openapi'
version = 'scm-1'

source = {
    url = 'git+https://github.com/tnt-skein/tnt-openapi.git',
    branch = 'main',
}

description = {
    summary = 'Описание API OpenAPI 3.0 из объявленных маршрутов tnt-router и форм tnt-data',
    detailed = [[
        Документ OpenAPI 3.0 — следствие объявлений, а не второй текст
        рядом с кодом: пути, способы и параметры пути даёт роутер
        (ограничения шаблона становятся схемами, необязательный участок
        и хвост — отдельными путями), схемы тел и ответов — формы
        tnt-data, параметры строки запроса — объявленный запрос, который
        приходит в описание операции аргументом и отдаёт их сам. Руками
        пишутся только слова, и описание операции ищется по имени
        маршрута.

        Маршрут API без описания, описание без маршрута, параметр,
        которого в пути нет, две операции на одном пути — отказ парой
        nil, problems со всеми расхождениями сразу. Документ, написанный
        руками, сверяется с маршрутами по способу и пути целиком.

        Зависимости — tnt-router (разбор шаблона), tnt-data (формы
        и их схемы) и tnt-must (проверки объявления). Покрытие строк
        и убитых мутантов — 100 %.
    ]],
    homepage = 'https://github.com/tnt-skein/tnt-openapi',
    issues_url = 'https://github.com/tnt-skein/tnt-openapi/issues',
    maintainer = 'tnt-skein',
    license = 'MIT',
    labels = { 'tarantool', 'openapi', 'http', 'router', 'api' },
}

dependencies = {
    'lua >= 5.1',
    -- Шаблон маршрута разбирает сам роутер: второй разбор разошёлся бы
    -- с первым при первом новом виде участка.
    'tnt-router',
    -- Формы: схемы тел и ответов и `components.schemas`.
    'tnt-data',
    -- Проверки объявления и аргументов на строке вызывающего.
    'tnt-must',
}

build = {
    type = 'builtin',
    modules = {
        ['tnt.openapi'] = 'tnt/openapi.lua',
        ['tnt.openapi.declare'] = 'tnt/openapi/declare.lua',
        ['tnt.openapi.document'] = 'tnt/openapi/document.lua',
        ['tnt.openapi.operation'] = 'tnt/openapi/operation.lua',
        ['tnt.openapi.paths'] = 'tnt/openapi/paths.lua',
        ['tnt.openapi.served'] = 'tnt/openapi/served.lua',
    },
}
