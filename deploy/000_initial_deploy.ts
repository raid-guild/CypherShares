import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deploy } = hre.deployments
    const getUnnamedAccounts = hre.getUnnamedAccounts

    const [deployer] = await getUnnamedAccounts()

    const controller = await deploy('Controller', {
        from: deployer,
        args: [deployer],
        log: true
    })

    await deploy('CSTokenCreator', {
        from: deployer,
        args: [controller.address],
        log: true
    })
};
export default func;