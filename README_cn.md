中文 | [English](README.md)
# Auctions 项目说明

这是一个基于 Foundry 的多拍卖智能合约工程，用于演示和测试多种常见拍卖机制在 Solidity 中的实现方式。项目围绕 ERC20 代币拍卖展开，包含合约源码、部署脚本、单元测试，以及若干用于 Sepolia 网络交互的 shell 脚本。

当前项目包含以下几类合约：

- 荷兰拍卖（Dutch Auction）：价格随时间递减，直到买家接受当前价格。
- 英式拍卖（English Auction）：公开竞价，出价最高者获胜。
- 维克里拍卖（Vickrey Auction）：先密封提交出价哈希，再公开揭示，最高出价者获胜，但按第二高有效出价支付。
- 拍卖测试代币（AuctionERC20）：用于测试和演示的 ERC20 代币。

说明：仓库中的合约文件名使用的是 `vickreyAuction.sol`，这是当前项目中的命名方式。

## 技术栈

- Solidity `^0.8.20`
- Foundry（`forge`、`cast`、`anvil`）
- OpenZeppelin Contracts

## 目录结构

```text
src/
  auctionERC20.sol        # 用于拍卖的 ERC20 代币
  dutchAuction.sol        # 荷兰拍卖实现
  englishAuction.sol      # 英式拍卖实现
  vickreyAuction.sol      # Commit-Reveal 的第二价格拍卖

script/
  auctionERC20.s.sol      # 部署 AuctionERC20
  dutchAuction.s.sol      # 部署 DutchAuction
  vickreyAuction.s.sol    # 部署 VickreyAuction

test/
  DutchAuction.t.sol
  EnglishAuction.t.sol
  VickreyAuction.t.sol

deploy.sh                 # 统一部署入口
approve.sh                # DutchAuction 的代币授权示例
buy.sh                    # DutchAuction 的购买示例
get_current_price.sh      # 查询 DutchAuction 当前价格
get_status.sh             # 查询 DutchAuction 状态
withdraw.sh               # 提现示例脚本
```

## 合约说明

### AuctionERC20

`AuctionERC20` 是一个最小化的 ERC20 合约，用作测试资产或演示拍卖标的。

构造参数：

- `name`
- `symbol`
- `initialSupply`
- `initialAccount`

部署后会将全部初始供应量 mint 给指定账户。

### DutchAuction

`DutchAuction` 用于拍卖固定数量的 ERC20 代币。卖家启动拍卖后，代币会先转入合约托管，价格则会在固定时间内从 `START_PRICE` 线性下降到 `MIN_PRICE`。

基本流程：

1. 卖家部署拍卖合约，设定代币数量、起拍价、最低价和持续时间。
2. 卖家先对拍卖合约执行 ERC20 `approve`。
3. 卖家调用 `start(token)` 启动拍卖。
4. 买家通过 `getCurrentPrice()` 查询当前价格，并调用 `buy()` 支付 ETH 购买。
5. 如果到期仍无人购买，卖家可以调用 `withdraw()` 取回代币。
6. 如果拍卖仍处于活跃状态，卖家也可以调用 `cancel()` 取消拍卖。

特点：

- 价格随时间递减。
- 买家一旦成交，立即完成结算。
- 多付的 ETH 会退回给买家。
- 拍卖期间代币由合约托管。

### EnglishAuction

`EnglishAuction` 是公开递增出价的拍卖模型。卖家在开始拍卖时将 ERC20 代币转入合约，竞拍者通过连续出更高的 ETH 竞价，最终最高出价者胜出。

基本流程：

1. 卖家部署合约，设置代币数量和起拍价。
2. 卖家先授权拍卖合约，然后调用 `startAuction(token, duration)` 启动拍卖。
3. 竞拍者调用 `bid()` 并发送更高的 ETH 出价。
4. 被超越的竞拍者金额会记入 `pendingReturns`，可后续自行提取。
5. 到达结束时间后，卖家调用 `doneAuction()` 完成结算。
6. 失败竞拍者可调用 `withdraw()` 取回自己可退还的 ETH。
7. 如果无人出价，卖家可以调用 `reclaim()` 回收代币。

特点：

- 最高公开出价获胜。
- 被超越的出价不会立刻退还，而是采用延迟提现模式。
- 一旦有有效竞价，卖家不能随意取消拍卖。

### VickreyAuction

`VickreyAuction` 实现了密封投标的第二价格拍卖，使用 commit-reveal 两阶段机制避免竞拍阶段泄露真实出价。

状态阶段：

1. `Initialized`
2. `Committing`
3. `Revealing`
4. `EndAuctioned`
5. `EndPhasedOut`

基本流程：

1. 卖家部署合约，设置 `START_PRICE`、`COMMIT_DURATION`、`REVEAL_DURATION`、`END_DURATION`。
2. 卖家先授权代币，再调用 `startAuction(token, tokenAmount)` 启动拍卖。
3. 竞拍者在链下计算 `keccak256(abi.encodePacked(bidAmount, secret))`。
4. 竞拍者调用 `commitBid(bidHash)`，并随交易发送足够的 ETH 作为押金。
5. 进入揭示阶段后，竞拍者调用 `revealBid(bidAmount, secret)` 公布真实出价。
6. 揭示结束后，在结束窗口内任意人可调用 `endAuction()` 完成竞价结果确认。
7. 卖家调用 `withdrawFund()` 提取成交价。
8. 胜者调用 `claim()` 领取 ERC20 代币，并退回超出最终成交价的 ETH。
9. 失败竞拍者调用 `withdraw()` 取回自己的押金。

特点：

- 提交阶段不会暴露真实出价。
- 最高有效出价者获胜。
- 若存在第二高有效出价，胜者按第二高价支付。
- 押金必须覆盖出价金额，否则揭示时会失败。

## 测试说明

项目已经包含 Foundry 单元测试，覆盖主要业务路径：

- `DutchAuction.t.sol`：测试代币托管、购买成交、到期回收、取消拍卖。
- `EnglishAuction.t.sol`：测试无人出价时回收、有出价时禁止取消、失败竞拍者提款、最终结算。
- `VickreyAuction.t.sol`：测试提交与揭示流程、重复提交失败、错误 secret 失败、第二价格结算、赢家与输家资金处理。

运行全部测试：

```bash
forge test
```

运行指定测试文件：

```bash
forge test --match-path test/VickreyAuction.t.sol
```

仅编译：

```bash
forge build
```

## 安装与初始化

如果本地尚未安装 Foundry：

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

安装依赖并编译：

```bash
forge install
forge build
```

## 部署方式

项目提供了统一部署脚本：

```bash
./deploy.sh [target] [rpc-url(optional)]
```

当前支持的部署目标：

- `auction-erc20`
- `dutch-auction`
- `vickrey-auction`

部署前需要设置环境变量：

```bash
export PRIVATE_KEY=0x<your_private_key>
```

默认 RPC：

```text
https://ethereum-sepolia.publicnode.com
```

示例：

```bash
./deploy.sh auction-erc20
./deploy.sh dutch-auction
./deploy.sh vickrey-auction
```

也可以直接使用 Foundry 原生命令部署。

部署 AuctionERC20：

```bash
forge script script/auctionERC20.s.sol:AuctionERC20Script \
  --rpc-url <RPC_URL> \
  --broadcast
```

部署 DutchAuction：

```bash
forge script script/dutchAuction.s.sol:DutchAuctionScript \
  --rpc-url <RPC_URL> \
  --broadcast
```

部署 VickreyAuction：

```bash
forge script script/vickreyAuction.s.sol:VickreyAuctionScript \
  --rpc-url <RPC_URL> \
  --broadcast
```

### 部署脚本参数

`auctionERC20.s.sol` 读取以下环境变量：

- `PRIVATE_KEY`
- `TOKEN_NAME`，默认 `Auction Token`
- `TOKEN_SYMBOL`，默认 `AUCT`
- `INITIAL_SUPPLY`，默认 `1000000 ether`
- `INITIAL_ACCOUNT`，默认部署者地址

`dutchAuction.s.sol` 读取以下环境变量：

- `PRIVATE_KEY`
- `TOKEN_AMOUNT`，默认 `100 ether`
- `START_PRICE`，默认 `1 ether`
- `MIN_PRICE`，默认 `0.01 ether`
- `DURATION`，默认 `5 minutes`

`vickreyAuction.s.sol` 读取以下环境变量：

- `PRIVATE_KEY`
- `START_PRICE`，默认 `1 ether`
- `COMMIT_DURATION`，默认 `5 minutes`
- `REVEAL_DURATION`，默认 `5 minutes`
- `END_DURATION`，默认 `5 minutes`

## 辅助 Shell 脚本

仓库根目录还提供了若干便捷脚本，主要用于和已部署的 Sepolia 合约快速交互：

- `approve.sh`：给 DutchAuction 合约做 ERC20 授权。
- `buy.sh`：对已部署的 DutchAuction 发起购买。
- `get_current_price.sh`：读取当前荷兰拍卖价格。
- `get_status.sh`：读取 DutchAuction 的状态值。
- `withdraw.sh`：调用目标合约的 `withdraw()`。

这些脚本目前包含硬编码地址，更适合做本地工具或调用示例。正式使用前请先检查并修改合约地址、私钥变量和 RPC 配置。

## 本地开发示例

启动本地区块链：

```bash
anvil
```

另开一个终端运行测试：

```bash
forge test -vv
```

如果要在本地节点上部署：

```bash
export PRIVATE_KEY=<anvil_private_key>
forge script script/auctionERC20.s.sol:AuctionERC20Script --rpc-url http://127.0.0.1:8545 --broadcast
forge script script/dutchAuction.s.sol:DutchAuctionScript --rpc-url http://127.0.0.1:8545 --broadcast
```

## 安全说明

- 合约使用了 `ReentrancyGuard` 和 OpenZeppelin 的 `SafeERC20` 来降低常见转账风险。
- 当前仓库更像一个学习型或原型型工程，而不是可直接上线生产环境的完整拍卖系统。
- 项目没有经过安全审计。
- 如果要进一步投入真实环境，建议补充 fuzz test、invariant test、权限审查、时序边界测试，以及对未揭示出价等情况的系统性设计。

## 项目总结

这个仓库适合用来学习和比较 Solidity 中三种经典拍卖模式的实现思路：

- Dutch Auction：递减价格，快速成交。
- English Auction：公开竞价，价高者得。
- Vickrey Auction：密封出价，赢家按第二高价支付。

如果你想系统理解拍卖机制、练习 ERC20 托管与结算逻辑、或者搭建一个 Foundry 风格的 Web3 合约实验项目，这个仓库就是一个很合适的起点。