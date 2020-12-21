import "module-alias/register";
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';
import { ether } from '@utils/common';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deploy, get } = hre.deployments
    const getUnnamedAccounts = hre.getUnnamedAccounts

    const [deployer] = await getUnnamedAccounts()

    const WETH_ADDRESSES = {
        kovan: "0xd0a1e359811322d97991e03f863a0c30c2cf029c",
        mainnet: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
    }

    let wethAddr
    if (hre.hardhatArguments.network !== 'kovan' && hre.hardhatArguments.network !== 'mainnet') {
        const weth = await deploy('WETH9', { from: deployer })
        wethAddr = weth.address
    } else {
        wethAddr = WETH_ADDRESSES[hre.hardhatArguments.network as keyof typeof WETH_ADDRESSES]
    }

    const controller = await get('Controller')
    const csTokenCreator = await get('CSTokenCreator')

    const basicIssuanceModule = await deploy('BasicIssuanceModule', {
        from: deployer,
        args: [controller.address],
        log: true
    })

    const navIssuanceModule = await deploy('NavIssuanceModule', {
        from: deployer,
        args: [controller.address, wethAddr],
        log: true
    })

    const governanceModule = await deploy('GovernanceModule', {
        from: deployer,
        args: [controller.address],
        log: true
    })

    const streamingFeeModule = await deploy('StreamingFeeModule', {
        from: deployer,
        args: [controller.address],
        log: true
    })

    const controllerContract = await ethers.getContractAt('Controller', controller.address)
    const initialized = await controllerContract.isInitialized()
    if (!initialized) {
        console.log('Initializing Controller Modules')
        await controllerContract.initialize(
            [csTokenCreator.address],
            [
                basicIssuanceModule.address,
                navIssuanceModule.address,
                governanceModule.address,
                streamingFeeModule.address
            ],
            [],
            []
        )
    } else {
        console.log("Controller already initialized.")
    }

    const sets = await controllerContract.getSets()

    if (sets.length == 0) {
        console.log("Creating default index csDEFI")
    
        const csTokenCreatorContract = await ethers.getContractAt('CSTokenCreator', csTokenCreator.address)
        await csTokenCreatorContract.create(
            [wethAddr],
            [ether(1)],
            [
                basicIssuanceModule.address,
                navIssuanceModule.address,
                governanceModule.address,
                streamingFeeModule.address
            ],
            deployer,
            "Cypher Shares Defi Index",
            "csDEFI"
        )
    } else {
        console.log('csDEFI index already created at', sets[0])
    }
};
export default func;