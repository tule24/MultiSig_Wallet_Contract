# Multisig Wallet Contract + Testing
![Solidity](https://img.shields.io/badge/Solidity-%23363636.svg?style=for-the-badge&logo=solidity&logoColor=white) ![JavaScript](https://img.shields.io/badge/javascript-%23323330.svg?style=for-the-badge&logo=javascript&logoColor=%23F7DF1E)

## Main function
### Wallet Factory contract
- `createWallet`: create new multisig wallet contract
- `updateOwner`: update owners of wallet
### Wallet Multisig contract
- `createTrans`: create a new transaction ID, make sure don't have any consensusID is pending
- `createCons `: create a new consensus ID, make sure don't have any ID is pending
- `vote`: vote to ID, each owner can only vote once per ID 
- `resolveTrans`: when the voting rate is enough, this function is called to resolve the transaction ID
- `resolveCons`: when the voting rate is enough, this function is called to resolve the consensus ID
- `createId`: private helper function, this function is called to create a new ID

Try running some of the following tasks:
```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.js
```
