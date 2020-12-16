// These utils will be provider-aware of the buidler interface
import { ethers } from "hardhat";
import { JsonRpcProvider } from "@ethersproject/providers"

import { Blockchain, ProtocolUtils } from "./common";

// Hardhat-Provider Aware Exports
const provider: JsonRpcProvider = ethers.provider as JsonRpcProvider;
export const getProtocolUtils = () => new ProtocolUtils(provider);
export const getBlockchainUtils = () => new Blockchain(provider);
export {
    divDown,
    ether,
    preciseMul
} from "./common";
export {
    getAccounts,
    getEthBalance,
    getLastBlockTimestamp,
    getProvider,
    getTransactionTimestamp,
    getWaffleExpect,
    addSnapshotBeforeRestoreAfterEach,
    getRandomAccount,
    getRandomAddress,
    increaseTimeAsync,
    mineBlockAsync,
} from "./hardhat";