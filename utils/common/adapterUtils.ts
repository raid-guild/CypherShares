import { BigNumber } from "@ethersproject/bignumber";
import { keccak256 } from "@ethersproject/keccak256";

export const addressToData = (address: string) => address.replace("0x", "000000000000000000000000");
export const bigNumberToData = (number: BigNumber) => number.toHexString().replace("0x", "").padStart(64, "0");
export const hashAdapterName = (name: string) => keccak256(new Buffer(name));