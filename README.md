# tnt-openapi

Описание API OpenAPI 3.0 для Tarantool из того, что уже объявлено в коде:
пути, способы и параметры пути — из маршрутов `tnt-router`, схемы тел
и ответов — из форм `tnt-data`, параметры строки запроса — из объявленного
запроса. Руками пишутся только слова, а документ, разошедшийся
с роутером, не собирается.

```lua
local data = require('tnt.data')
local openapi = require('tnt.openapi')
local router = require('tnt.router')

local Customer = data.define({ name = 'Customer', fields = { { 'id', 'integer', min = 1 }, { 'name', 'string' } } })
local NewCustomer = data.define({ name = 'NewCustomer', fields = { { 'name', 'string', min = 1, max = 64 } } })
local Problem = data.define({ name = 'Problem', fields = { { 'title', 'string' }, { 'status', 'integer' } } })

local web = router.new()

web.group('/api/v1', { name = 'customers.' }, function(r)
    r.get('/customers/:id<int>', show, { name = 'show' })
    r.post('/customers', create, { name = 'create' })
end)

local Api = openapi.define({
    title = 'Магазин',
    version = '1',
    servers = { { url = '/api/v1' } },
    refusal = { schema = Problem, media = 'application/problem+json' },
    operations = {
        ['customers.show'] = {
            summary = 'Клиент по номеру',
            params = { id = 'Номер клиента' },
            responses = { [200] = Customer, [404] = 'Клиента нет' },
        },
        ['customers.create'] = {
            summary = 'Завести клиента',
            body = NewCustomer,
            responses = { [201] = Customer, [422] = 'Поля не прошли проверку' },
        },
    },
})

local document = assert(Api.document(web))      -- таблица OpenAPI 3.0: в JSON, в YAML, в проверку
document.paths['/customers/{id}'].get.parameters[1].schema
--> { type = 'integer' }

web.delete('/api/v1/customers/:id<int>', remove, { name = 'customers.remove' })

Api.document(web)                                 -- маршрут без описания — документа нет
--> nil, { 'Маршрут customers.remove (DELETE /api/v1/customers/:id<int>) не описан.' }

openapi.served(document, web)                     -- готовый документ против маршрутов
--> nil, { 'Операция DELETE /api/v1/customers/{id} обслуживается, но не описана.' }
```

Зависимости: [`tnt-router`](https://github.com/tnt-skein/tnt-router)
(разбор шаблона маршрута), [`tnt-data`](https://github.com/tnt-skein/tnt-data)
(формы и их схемы) и [`tnt-must`](https://github.com/tnt-skein/tnt-must)
(проверки объявления). Запрос [`tnt-query`](https://github.com/tnt-skein/tnt-query)
приходит в описание операции аргументом, и пакет его не тянет. Настроек
и состояния у пакета нет.

## Зачем

Описание API, которое пишут рядом с кодом руками, расходится с ним
молча: маршрут появился и не описан, поле переименовали в форме и забыли
в документе. Пакет делает документ следствием объявлений:

- **Документ — из объявлений.** Путь, способ и параметр пути
  берутся у роутера, ограничение шаблона `<int>` становится схемой
  параметра, форма — ссылкой `#/components/schemas/<имя>`, а все формы,
  вложенные тоже, — `components.schemas`.
- **Неполный документ не собирается.** Маршрут API без описания,
  описание без маршрута, слово о параметре, которого нет в пути, две
  операции на одном пути — отказ парой `nil, problems` со всеми
  расхождениями сразу.
- **Необязательный участок и хвост честно.** Адрес с участком и без
  него — два пути описания, опознаватель операции — у длинного.
- **Отказ один на всё API.** Тело отказа объявляется один раз, получают
  его все отказы, описанные словом, а `default` есть у каждой операции:
  упавший обработчик отвечает 500 на любом адресе.
- **Сверка документа, написанного руками.** `openapi.served` сличает его
  операции с маршрутами по способу и пути целиком.

## Установка

```sh
tt rocks install tnt-openapi --server=https://tnt-skein.github.io/rocks
```

Или из исходников:

```sh
git clone https://github.com/tnt-skein/tnt-openapi.git
cd tnt-openapi && tt rocks make
```

## Как пользоваться

| Вызов | Что делает |
|---|---|
| `openapi.define(spec)` | объявляет описание: `title`, `version`, `servers`, `select`, `refusal`, `operations`…; негодное — исключение |
| `Api.document(router)` | документ OpenAPI 3.0 таблицей либо `nil, problems` |
| `openapi.served(document, router, opts)` | сверка готового документа с маршрутами: `true` либо `nil, problems` |
| `openapi.VERSION` | версия OpenAPI документа — `3.0.3` |

Описание операции ищется по имени маршрута: имя переживает перенос
группы под другое начало пути, а шаблон — нет. Какие маршруты составляют
API, решает `select`; по умолчанию — все именованные. Операция называет
`summary`, `params` (слова параметров пути), `query` (объявленный
запрос: параметры строки запроса), `body` и `responses`; ответ — форма,
слово либо таблица `{ description, schema, media }`:

```lua
responses = {
    [200] = Customer,                                        -- форма: слово — about формы, иначе имя
    [404] = 'Клиента нет',                                   -- слово: у отказа — тело отказа описания
    [207] = { description = 'Сделано не всё', schema = Report, media = 'application/json' },
}
```

Путь документа считается от пути первого сервера: `/api/v1` в `servers`
и маршрут `/api/v1/customers` дают путь `/customers`. Роутер —
экземпляр `tnt-router` либо что угодно с `routes()`, отдающим маршруты
таблицами `{ method, pattern, name }`.

## Проверки

```sh
make deps          # luatest, luacheck, luacov с cluacov, зависимости пакета и tnt-query в .rocks
make check         # форматирование, линт, проверки, покрытие с порогом 100 %
make mutants-all   # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
```

Покрытие строк — 100 %, убитых мутантов — 100 % (70 проверок,
277 мутантов в шести модулях). Внешней службы у пакета нет: роутер
в проверках настоящий, документ и отказы сличаются целиком и дословно.

## Документ

Полное описание с обоснованием решений: [docs/openapi.md](docs/openapi.md).

## Лицензия

MIT.
