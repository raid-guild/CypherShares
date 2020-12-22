# CypherShares Protocol Contract Repository

CypherShares is a new index protocol that offers the most comprehensive and liquid index products in crypto. Our initial index will be the CypherShares DeFi Index (csDEFI) and will hold at least 100 tokens of the best DeFi projects. CypherShares will use a novel Threshold Farming strategy in order to incentivise index liquidity.

---

## Deployments

### Kovan Testnet:

- Controller: 0x2E0F1bA21146ff234B0A07E298c70490ff54ffaD
- CSTokenCreator: 0xd268f4052E7bB0dA6724151CF20a196b8875D983
- BasicIssuanceModule: 0x0f0eE18189FB5472226A7E54e0c7a3BB1155705D
- NavIssuanceModule: 0xE4F09C87E5DC4e309f84729d525C681751496321
- GovernanceModule: 0x31Dca181eF571FC86eCE79d85D311667d122F95a
- StreamingFeeModule: 0x10974dC97962677f0d913E89ef6b93c2941B2332

- Example Index (csDEFI): 0x233Df1d25E2b4731d37E85a994C8B6F84F4Ef72D

---
## Tooling

- [Hardhat](https://github.com/nomiclabs/hardhat): compile and run the smart contracts on a local development network
- [TypeChain](https://github.com/ethereum-ts/TypeChain): generate TypeScript types for smart contracts
- [Ethers](https://github.com/ethers-io/ethers.js/): renowned Ethereum library and wallet implementation
- [Waffle](https://github.com/EthWorks/Waffle): tooling for writing comprehensive smart contract tests
- [Solhint](https://github.com/protofire/solhint): linter
- [Solcover](https://github.com/sc-forks/solidity-coverage) code coverage
- [Prettier Plugin Solidity](https://github.com/prettier-solidity/prettier-plugin-solidity): code formatter
---
## Usage

### Pre Requisites

Before running any command, make sure to install dependencies:

```sh
$ yarn install
```

### Compile

Compile the smart contracts with Hardhat:

```sh
$ yarn compile
```

### TypeChain

Compile the smart contracts and generate TypeChain artifacts:

```sh
$ yarn build
```

### Lint Solidity

Lint the Solidity code:

```sh
$ yarn lint:sol
```

### Lint TypeScript

Lint the TypeScript code:

```sh
$ yarn lint:ts
```

### Test

Run the Mocha tests:

```sh
$ yarn test
```

### Coverage

Generate the code coverage report:

```sh
$ yarn coverage
```

### Clean

Delete the smart contract artifacts, the coverage reports and the Hardhat cache:

```sh
$ yarn clean
```
