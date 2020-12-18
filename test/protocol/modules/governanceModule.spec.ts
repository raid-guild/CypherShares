import "module-alias/register";

import { Address, Account, Bytes } from "@utils/types";
import { GovernanceModule, GovernanceAdapterMock, CSToken } from "@utils/contracts";
import DeployHelper from "@utils/deploys";
import {
    addSnapshotBeforeRestoreAfterEach,
    ether,
    getAccounts,
    getWaffleExpect,
    getSystemFixture,
    getRandomAccount,
    getRandomAddress,
    bigNumberToData,
} from "@utils/index";
import { SystemFixture } from "@utils/fixtures";
import { BigNumber } from "@ethersproject/bignumber";
import { ADDRESS_ZERO, ONE, TWO, ZERO, EMPTY_BYTES } from "@utils/constants";

const expect = getWaffleExpect();

describe("GovernanceModule", () => {
    let owner: Account;
    let deployer: DeployHelper;
    let setup: SystemFixture;

    let governanceModule: GovernanceModule;
    let governanceAdapterMock: GovernanceAdapterMock;
    let governanceAdapterMock2: GovernanceAdapterMock;

    const governanceAdapterMockIntegrationName: string = "MOCK_GOV";
    const governanceAdapterMockIntegrationName2: string = "MOCK2_GOV";

    before(async () => {
        [
            owner,
        ] = await getAccounts();

        deployer = new DeployHelper(owner.wallet);
        setup = getSystemFixture(owner.address);
        await setup.initialize();

        governanceModule = await deployer.modules.deployGovernanceModule(setup.controller.address);
        await setup.controller.addModule(governanceModule.address);

        governanceAdapterMock = await deployer.mocks.deployGovernanceAdapterMock(ZERO);
        await setup.integrationRegistry.addIntegration(governanceModule.address, governanceAdapterMockIntegrationName, governanceAdapterMock.address);
        governanceAdapterMock2 = await deployer.mocks.deployGovernanceAdapterMock(ONE);
        await setup.integrationRegistry.addIntegration(governanceModule.address, governanceAdapterMockIntegrationName2, governanceAdapterMock2.address);
    });

    addSnapshotBeforeRestoreAfterEach();

    describe("#constructor", async () => {
        let subjectController: Address;

        beforeEach(async () => {
            subjectController = setup.controller.address;
        });

        async function subject(): Promise<any> {
            return deployer.modules.deployGovernanceModule(subjectController);
        }

        it("should set the correct controller", async () => {
            const governanceModule = await subject();

            const controller = await governanceModule.controller();
            expect(controller).to.eq(subjectController);
        });
    });

    describe("#initialize", async () => {
        let csToken: CSToken;
        let subjectCSToken: Address;
        let subjectCaller: Account;

        beforeEach(async () => {
            csToken = await setup.createCSToken(
                [setup.weth.address],
                [ether(1)],
                [governanceModule.address]
            );
            subjectCSToken = csToken.address;
            subjectCaller = owner;
        });

        async function subject(): Promise<any> {
            return governanceModule.connect(subjectCaller.wallet).initialize(subjectCSToken);
        }

        it("should enable the Module on the CSToken", async () => {
            await subject();
            const isModuleEnabled = await csToken.isInitializedModule(governanceModule.address);
            expect(isModuleEnabled).to.eq(true);
        });

        describe("when the caller is not the CSToken manager", async () => {
            beforeEach(async () => {
                subjectCaller = await getRandomAccount();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be the CSToken manager");
            });
        });

        describe("when module is in NONE state", async () => {
            beforeEach(async () => {
                await subject();
                await csToken.removeModule(governanceModule.address);
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be pending initialization");
            });
        });

        describe("when module is in INITIALIZED state", async () => {
            beforeEach(async () => {
                await subject();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be pending initialization");
            });
        });

        describe("when the CSToken is not enabled on the controller", async () => {
            beforeEach(async () => {
                const nonEnabledCSToken = await setup.createNonControllerEnabledCSToken(
                    [setup.weth.address],
                    [ether(1)],
                    [governanceModule.address]
                );

                subjectCSToken = nonEnabledCSToken.address;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be controller-enabled CSToken");
            });
        });
    });

    describe("#removeModule", async () => {
        let csToken: CSToken;
        let subjectModule: Address;
        let subjectCaller: Account;

        beforeEach(async () => {
            csToken = await setup.createCSToken(
                [setup.weth.address],
                [ether(1)],
                [governanceModule.address]
            );

            subjectModule = governanceModule.address;
            subjectCaller = owner;

            await governanceModule.initialize(csToken.address);
        });

        async function subject(): Promise<any> {
            return csToken.connect(subjectCaller.wallet).removeModule(subjectModule);
        }

        it("should properly remove the module and settings", async () => {
            await subject();

            const isModuleEnabled = await csToken.isInitializedModule(subjectModule);
            expect(isModuleEnabled).to.eq(false);
        });
    });

    describe("#vote", async () => {
        let csToken: CSToken;
        let isInitialized: boolean;

        let subjectCaller: Account;
        let subjectIntegration: string;
        let subjectProposalId: BigNumber;
        let subjectSupport: boolean;
        let subjectCSToken: Address;
        let subjectData: Bytes;

        before(async () => {
            isInitialized = true;
        });

        beforeEach(async () => {
            csToken = await setup.createCSToken(
                [setup.weth.address],
                [ether(1)],
                [governanceModule.address]
            );

            subjectCaller = owner;

            subjectProposalId = ZERO;
            subjectCSToken = csToken.address;
            subjectIntegration = governanceAdapterMockIntegrationName;
            subjectSupport = true;
            subjectData = EMPTY_BYTES;

            if (isInitialized) {
                await governanceModule.initialize(csToken.address);
            }
        });

        async function subject(): Promise<any> {
            return governanceModule.connect(subjectCaller.wallet).vote(
                subjectCSToken,
                subjectIntegration,
                subjectProposalId,
                subjectSupport,
                subjectData
            );
        }

        it("should vote in proposal for the governance integration", async () => {
            const proposalStatusBefore = await governanceAdapterMock.proposalToVote(subjectProposalId);
            expect(proposalStatusBefore).to.eq(false);

            await subject();

            const proposalStatusAfter = await governanceAdapterMock.proposalToVote(subjectProposalId);
            expect(proposalStatusAfter).to.eq(true);
        });

        it("emits the correct ProposalVoted event", async () => {
            await expect(subject()).to.emit(governanceModule, "ProposalVoted").withArgs(
                subjectCSToken,
                governanceAdapterMock.address,
                subjectProposalId,
                subjectSupport
            );
        });

        describe("when the governance integration is not present", async () => {
            beforeEach(async () => {
                subjectIntegration = await getRandomAddress();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be valid adapter");
            });
        });

        describe("when caller is not manager", async () => {
            beforeEach(async () => {
                subjectCaller = await getRandomAccount();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be the CSToken manager");
            });
        });

        describe("when module is not initialized", async () => {
            before(async () => {
                isInitialized = false;
            });

            after(async () => {
                isInitialized = true;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });

        describe("when CSToken is not valid", async () => {
            beforeEach(async () => {
                const nonEnabledCSToken = await setup.createNonControllerEnabledCSToken(
                    [setup.weth.address],
                    [ether(1)],
                    [governanceModule.address]
                );

                subjectCSToken = nonEnabledCSToken.address;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });
    });

    describe("#propose", async () => {
        let csToken: CSToken;
        let isInitialized: boolean;

        let subjectCaller: Account;
        let subjectIntegration: string;
        let subjectCSToken: Address;
        let subjectProposalData: Bytes;

        before(async () => {
            isInitialized = true;
        });

        beforeEach(async () => {
            csToken = await setup.createCSToken(
                [setup.weth.address],
                [ether(1)],
                [governanceModule.address]
            );

            // Get proposal data for mock governance adapter
            const proposalData = "0x" + bigNumberToData(TWO);

            subjectCaller = owner;

            subjectCSToken = csToken.address;
            subjectIntegration = governanceAdapterMockIntegrationName;
            subjectProposalData = proposalData;

            if (isInitialized) {
                await governanceModule.initialize(csToken.address);
            }
        });

        async function subject(): Promise<any> {
            return governanceModule.connect(subjectCaller.wallet).propose(
                subjectCSToken,
                subjectIntegration,
                subjectProposalData
            );
        }

        it("should create a new proposal for the governance integration", async () => {
            const proposalStatusBefore = await governanceAdapterMock.proposalCreated(TWO);
            expect(proposalStatusBefore).to.eq(false);

            await subject();

            const proposalStatusAfter = await governanceAdapterMock.proposalCreated(TWO);
            expect(proposalStatusAfter).to.eq(true);
        });

        it("emits the correct ProposalCreated event", async () => {
            await expect(subject()).to.emit(governanceModule, "ProposalCreated").withArgs(
                subjectCSToken,
                governanceAdapterMock.address,
                subjectProposalData
            );
        });

        describe("when the governance integration is not present", async () => {
            beforeEach(async () => {
                subjectIntegration = await getRandomAddress();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be valid adapter");
            });
        });

        describe("when caller is not manager", async () => {
            beforeEach(async () => {
                subjectCaller = await getRandomAccount();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be the CSToken manager");
            });
        });

        describe("when module is not initialized", async () => {
            before(async () => {
                isInitialized = false;
            });

            after(async () => {
                isInitialized = true;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });

        describe("when CSToken is not valid", async () => {
            beforeEach(async () => {
                const nonEnabledCSToken = await setup.createNonControllerEnabledCSToken(
                    [setup.weth.address],
                    [ether(1)],
                    [governanceModule.address]
                );

                subjectCSToken = nonEnabledCSToken.address;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });
    });

    describe("#delegate", async () => {
        let csToken: CSToken;
        let isInitialized: boolean;

        let subjectCaller: Account;
        let subjectIntegration: string;
        let subjectCSToken: Address;
        let subjectDelegatee: Address;

        before(async () => {
            isInitialized = true;
        });

        beforeEach(async () => {
            csToken = await setup.createCSToken(
                [setup.weth.address],
                [ether(1)],
                [governanceModule.address]
            );

            subjectCaller = owner;

            subjectCSToken = csToken.address;
            subjectIntegration = governanceAdapterMockIntegrationName;
            subjectDelegatee = owner.address; // Delegate to owner

            if (isInitialized) {
                await governanceModule.initialize(csToken.address);
            }
        });

        async function subject(): Promise<any> {
            return governanceModule.connect(subjectCaller.wallet).delegate(
                subjectCSToken,
                subjectIntegration,
                subjectDelegatee,
            );
        }

        it("should delegate to the correct ETH address", async () => {
            await subject();

            const delegatee = await governanceAdapterMock.delegatee();
            expect(delegatee).to.eq(subjectDelegatee);
        });

        it("emits the correct VoteDelegated event", async () => {
            await expect(subject()).to.emit(governanceModule, "VoteDelegated").withArgs(
                subjectCSToken,
                governanceAdapterMock.address,
                subjectDelegatee
            );
        });

        describe("when the governance integration is not present", async () => {
            beforeEach(async () => {
                subjectIntegration = await getRandomAddress();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be valid adapter");
            });
        });

        describe("when caller is not manager", async () => {
            beforeEach(async () => {
                subjectCaller = await getRandomAccount();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be the CSToken manager");
            });
        });

        describe("when module is not initialized", async () => {
            before(async () => {
                isInitialized = false;
            });

            after(async () => {
                isInitialized = true;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });

        describe("when CSToken is not valid", async () => {
            beforeEach(async () => {
                const nonEnabledCSToken = await setup.createNonControllerEnabledCSToken(
                    [setup.weth.address],
                    [ether(1)],
                    [governanceModule.address]
                );

                subjectCSToken = nonEnabledCSToken.address;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });
    });

    describe("#register", async () => {
        let csToken: CSToken;
        let isInitialized: boolean;

        let subjectCaller: Account;
        let subjectIntegration: string;
        let subjectCSToken: Address;

        before(async () => {
            isInitialized = true;
        });

        beforeEach(async () => {
            csToken = await setup.createCSToken(
                [setup.weth.address],
                [ether(1)],
                [governanceModule.address]
            );

            subjectCaller = owner;

            subjectCSToken = csToken.address;
            subjectIntegration = governanceAdapterMockIntegrationName;

            if (isInitialized) {
                await governanceModule.initialize(csToken.address);
            }
        });

        async function subject(): Promise<any> {
            return governanceModule.connect(subjectCaller.wallet).register(
                subjectCSToken,
                subjectIntegration,
            );
        }

        it("should register the CSToken for voting", async () => {
            await subject();

            const delegatee = await governanceAdapterMock.delegatee();
            expect(delegatee).to.eq(subjectCSToken);
        });

        it("emits the correct RegistrationSubmitted event", async () => {
            await expect(subject()).to.emit(governanceModule, "RegistrationSubmitted").withArgs(
                subjectCSToken,
                governanceAdapterMock.address
            );
        });

        describe("when the governance integration is not present", async () => {
            beforeEach(async () => {
                subjectIntegration = await getRandomAddress();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be valid adapter");
            });
        });

        describe("when caller is not manager", async () => {
            beforeEach(async () => {
                subjectCaller = await getRandomAccount();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be the CSToken manager");
            });
        });

        describe("when module is not initialized", async () => {
            before(async () => {
                isInitialized = false;
            });

            after(async () => {
                isInitialized = true;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });

        describe("when CSToken is not valid", async () => {
            beforeEach(async () => {
                const nonEnabledCSToken = await setup.createNonControllerEnabledCSToken(
                    [setup.weth.address],
                    [ether(1)],
                    [governanceModule.address]
                );

                subjectCSToken = nonEnabledCSToken.address;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });
    });

    describe("#revoke", async () => {
        let csToken: CSToken;
        let isInitialized: boolean;

        let subjectCaller: Account;
        let subjectIntegration: string;
        let subjectCSToken: Address;

        before(async () => {
            isInitialized = true;
        });

        beforeEach(async () => {
            csToken = await setup.createCSToken(
                [setup.weth.address],
                [ether(1)],
                [governanceModule.address]
            );

            subjectCaller = owner;

            subjectCSToken = csToken.address;
            subjectIntegration = governanceAdapterMockIntegrationName;

            if (isInitialized) {
                await governanceModule.initialize(csToken.address);
            }
        });

        async function subject(): Promise<any> {
            return governanceModule.connect(subjectCaller.wallet).revoke(
                subjectCSToken,
                subjectIntegration,
            );
        }

        it("should revoke the CSToken for voting", async () => {
            await subject();

            const delegatee = await governanceAdapterMock.delegatee();
            expect(delegatee).to.eq(ADDRESS_ZERO);
        });

        it("emits the correct RegistrationRevoked event", async () => {
            await expect(subject()).to.emit(governanceModule, "RegistrationRevoked").withArgs(
                subjectCSToken,
                governanceAdapterMock.address
            );
        });

        describe("when the governance integration is not present", async () => {
            beforeEach(async () => {
                subjectIntegration = await getRandomAddress();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be valid adapter");
            });
        });

        describe("when caller is not manager", async () => {
            beforeEach(async () => {
                subjectCaller = await getRandomAccount();
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be the CSToken manager");
            });
        });

        describe("when module is not initialized", async () => {
            before(async () => {
                isInitialized = false;
            });

            after(async () => {
                isInitialized = true;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });

        describe("when CSToken is not valid", async () => {
            beforeEach(async () => {
                const nonEnabledCSToken = await setup.createNonControllerEnabledCSToken(
                    [setup.weth.address],
                    [ether(1)],
                    [governanceModule.address]
                );

                subjectCSToken = nonEnabledCSToken.address;
            });

            it("should revert", async () => {
                await expect(subject()).to.be.revertedWith("Must be a valid and initialized CSToken");
            });
        });
    });
});