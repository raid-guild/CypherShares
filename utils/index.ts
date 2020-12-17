// These utils will be provider-aware of the buidler interface
import { ethers } from "hardhat";
import { Address } from "./types";
import { JsonRpcProvider } from "@ethersproject/providers"

import { SystemFixture } from "./fixtures";
import { Blockchain, ProtocolUtils } from "./common";

// Hardhat-Provider Aware Exports
const provider: JsonRpcProvider = ethers.provider as JsonRpcProvider;
export const getSystemFixture = (ownerAddress: Address) => new SystemFixture(provider, ownerAddress);
export const getProtocolUtils = () => new ProtocolUtils(provider);
export const getBlockchainUtils = () => new Blockchain(provider);
export {
    divDown,
    ether,
    bitcoin,
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