# TripFund

TripFund — Foundry-проект для сбора средств на поездку команды в одном ERC-20. V1 реализует взносы, успешный вывод организатору и возвраты при недостижении цели. V2 обновляет тот же Transparent Proxy и добавляет взносы за другого участника.

## Возможности

- Взносы через `SafeERC20.safeTransferFrom`.
- Исторический учёт `contributions` и `totalRaised`.
- Однократный вывод организатором после успешного сбора.
- Независимые полные возвраты при неудачном сборе.
- Игнорирование прямых переводов ERC-20 в бухгалтерском учёте.
- OpenZeppelin 5.x Transparent Proxy с атомарной инициализацией.
- Обновление V1 → V2 владельцем созданного прокси контракта `ProxyAdmin`.
- `contributeFor`, где платит `msg.sender`, а вклад и право возврата получает beneficiary.
- Официальная проверка storage layout через OpenZeppelin Upgrades Core.

## Структура

```text
src/TripFund.sol
src/TripFundV2.sol
src/mocks/MockToken.sol
src/mocks/RevertingToken.sol
test/TripFund.t.sol
test/TripFundUpgrade.t.sol
script/Deploy.s.sol
script/Upgrade.s.sol
.github/workflows/test.yml
foundry.toml
remappings.txt
package.json
package-lock.json
```

## Версии

- Foundry `1.5.1-stable`.
- Solidity `0.8.27`.
- `forge-std v1.17.0`, commit `f3dae6e6ee381f25eb6a246f7da9b85c91a68219`.
- OpenZeppelin Contracts `5.7.0`.
- OpenZeppelin Contracts Upgradeable `5.7.0`.
- OpenZeppelin Upgrades Core `1.46.0`.
- Node.js `24` для локальной проверки и CI.

`forge-std` закреплён как Git submodule. OpenZeppelin-пакеты закреплены в `package-lock.json` с npm integrity hashes.

## Требования

- Git.
- Foundry.
- Node.js 24 и npm.

На Windows Foundry устанавливается нативными `win32_amd64` бинарниками из официального stable-релиза. Отдельная установка Solidity не требуется: Forge загружает `solc 0.8.27` по `foundry.toml`.

## Установка

```powershell
git clone --recurse-submodules <repository-url>
Set-Location <repository-directory>
npm ci --ignore-scripts
```

Если проект уже клонирован без submodules:

```powershell
git submodule update --init --recursive
npm ci --ignore-scripts
```

## Проверка

```powershell
forge fmt --check
forge clean
forge build
npm run validate:upgrade
forge test
forge test -vvv
```

После точечного запуска тестов OpenZeppelin validator может обнаружить partial build-info. Перед validation всегда выполняйте `forge clean` и полный `forge build`.

Validation использует явные параметры `--contract` и `--reference`, поэтому NatSpec-аннотации в Solidity не нужны. Флаг `--unsafeAllow constructor` применяется только к конструкторам, вызывающим `_disableInitializers()`. Проверка storage layout не отключается.

## Логика сбора

Параметры `token`, `organizer`, `goal` и `deadline` устанавливаются один раз через `initialize` при создании прокси.

Взносы разрешены только при `block.timestamp < deadline`. После наступления дедлайна:

- при `totalRaised >= goal` организатор один раз получает ровно `totalRaised`;
- при `totalRaised < goal` каждый участник самостоятельно возвращает свой полный учтённый вклад.

`totalRaised` — историческая сумма успешно принятых взносов. Она не уменьшается после вывода или возвратов и не равна текущему токенному балансу прокси.

Обычный `token.transfer(proxy, amount)` не меняет `totalRaised` и `contributions`. Такие токены не входят в выплаты и остаются на прокси.

## Локальный Anvil

Запустите узел в отдельном PowerShell:

```powershell
anvil
```

Для локальной демонстрации используйте один из тестовых приватных ключей, которые Anvil выводит при запуске.

Создайте тестовый токен:

```powershell
$env:PRIVATE_KEY = "<anvil-private-key>"
forge create src/mocks/MockToken.sol:MockToken --rpc-url http://127.0.0.1:8545 --private-key $env:PRIVATE_KEY --broadcast
```

Сохраните выведенный адрес токена и задайте параметры сбора:

```powershell
$env:TOKEN_ADDRESS = "<mock-token-address>"
$env:ORGANIZER = "<organizer-address>"
$env:PROXY_OWNER = "<proxy-admin-owner-address>"
$env:GOAL = "1000000000000000000000"
$env:DEADLINE = "<future-unix-timestamp>"
forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
```

Скрипт выводит адреса V1 implementation, proxy и фактически созданного `ProxyAdmin`.

## Approve и взнос

Spender всегда является адресом прокси:

```powershell
$env:RPC_URL = "http://127.0.0.1:8545"
$env:PROXY_ADDRESS = "<proxy-address>"
$env:AMOUNT = "100000000000000000000"
cast send $env:TOKEN_ADDRESS "approve(address,uint256)" $env:PROXY_ADDRESS $env:AMOUNT --rpc-url $env:RPC_URL --private-key $env:PRIVATE_KEY
cast send $env:PROXY_ADDRESS "contribute(uint256)" $env:AMOUNT --rpc-url $env:RPC_URL --private-key $env:PRIVATE_KEY
```

Для тестового `MockToken` баланс можно выдать вызовом `mint`:

```powershell
cast send $env:TOKEN_ADDRESS "mint(address,uint256)" "<participant-address>" $env:AMOUNT --rpc-url $env:RPC_URL --private-key $env:PRIVATE_KEY
```

## Обновление до V2

Обновление выполняется владельцем `ProxyAdmin` до дедлайна:

```powershell
$env:PRIVATE_KEY = "<proxy-admin-owner-private-key>"
$env:PROXY_ADDRESS = "<proxy-address>"
forge clean
forge build
npm run validate:upgrade
forge script script/Upgrade.s.sol:Upgrade --rpc-url http://127.0.0.1:8545 --broadcast
```

После обновления адрес прокси, параметры, вклады, `totalRaised`, флаг вывода и токенный баланс сохраняются. Обычный `contribute` продолжает работать.

Взнос за другого участника:

```powershell
$env:BENEFICIARY = "<beneficiary-address>"
cast send $env:TOKEN_ADDRESS "approve(address,uint256)" $env:PROXY_ADDRESS $env:AMOUNT --rpc-url $env:RPC_URL --private-key $env:PRIVATE_KEY
cast send $env:PROXY_ADDRESS "contributeFor(address,uint256)" $env:BENEFICIARY $env:AMOUNT --rpc-url $env:RPC_URL --private-key $env:PRIVATE_KEY
```

Токены списываются с отправителя транзакции. Вклад учитывается за beneficiary, и при неудачном сборе именно beneficiary вызывает `refund()`.

## Тестовые сценарии

`TripFund.t.sol` проверяет:

- валидацию всех параметров инициализации;
- два участника и повторные взносы;
- недостаточные баланс и allowance;
- полный revert при ошибках токена;
- временные границы дедлайна;
- сбор ровно goal и выше goal;
- независимые возвраты при сумме ниже goal;
- запрет чужих и повторных выплат;
- остаток прямых переводов после вывода и возвратов.

`TripFundUpgrade.t.sol` проверяет:

- реальный адрес и владельца `ProxyAdmin`;
- запрет обновления посторонними и организатором;
- сохранение адреса прокси и всего состояния V1;
- обычный взнос после обновления;
- `contributeFor` и отдельные роли payer и beneficiary;
- возврат beneficiary при провале сбора;
- запрет повторной и прямой инициализации.
