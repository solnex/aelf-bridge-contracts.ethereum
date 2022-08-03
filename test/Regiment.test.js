const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
describe("Regiment", function () {
    async function deployRegimentFixture() {
        // Contracts are deployed using the first signer/account by default
        const _memberJoinLimit = 10;
        const _regimentLimit = 20;
        const _maximumAdminsCount = 5;

        const [owner, otherAccount0, otherAccount1] = await ethers.getSigners();
        const Regiment = await ethers.getContractFactory("Regiment");
        const regiment = await Regiment.deploy(_memberJoinLimit, _regimentLimit, _maximumAdminsCount);
        return { regiment, owner, otherAccount0, otherAccount1 };
    }
    describe("deploy", function () {
        describe("GetController test", function () {
            it("Should be contract deployer", async function () {
                const { regiment, owner } = await loadFixture(deployRegimentFixture);
                expect(await regiment.GetController()).to.equal(owner.address);
            });
        })
    });

    describe("Action fuctionTest", function () {
        describe("create regiment test", function () {
            it("Should emit the RegimentCreated event", async function () {
                const { regiment, owner, otherAccount0, otherAccount1 } = await loadFixture(deployRegimentFixture);

                const _manager = otherAccount0.address;
                const _initialMemberList = [otherAccount0.address, otherAccount1.address];
                const _isApproveToJoin = false;
                await expect(regiment.CreateRegiment(_manager, _initialMemberList, _isApproveToJoin)).to.emit(regiment, "RegimentCreated");
            });

            it("Should emit the RegimentCreated event with certain args", async function () {
                const { regiment, owner, otherAccount0, otherAccount1 } = await loadFixture(deployRegimentFixture);
                const interface = new ethers.utils.Interface(["event RegimentCreated(uint256 create_time, address manager,address[] InitialMemberList,bytes32 regimentId)"]);
                const _manager = otherAccount0.address;
                const _initialMemberList = [otherAccount0.address, otherAccount1.address];
                const _isApproveToJoin = false;
                var tx = await regiment.CreateRegiment(_manager, _initialMemberList, _isApproveToJoin);
                const receipt = await tx.wait();

                for (const event of receipt.events) {
                    console.log(`Event ${event.event} with args ${event.args}`);
                }
                const data = receipt.logs[0].data;
                const topics = receipt.logs[0].topics;
                const event = interface.decodeEventLog("RegimentCreated", data, topics);
                expect(event.manager).to.equal(otherAccount0.address);
            });

            it("Should create correctly", async function () {
                const { regiment, owner, otherAccount0, otherAccount1 } = await loadFixture(deployRegimentFixture);
                const interface = new ethers.utils.Interface(["event RegimentCreated(uint256 create_time, address manager,address[] InitialMemberList,bytes32 regimentId)"]);
                const _manager = otherAccount0.address;
                const _initialMemberList = [otherAccount0.address, otherAccount1.address];
                const _isApproveToJoin = false;
                var tx = await regiment.CreateRegiment(_manager, _initialMemberList, _isApproveToJoin);
                const receipt = await tx.wait();
                const data = receipt.logs[0].data;
                const topics = receipt.logs[0].topics;
                const event = interface.decodeEventLog("RegimentCreated", data, topics);
                var regimentInfoForView = await regiment.GetRegimentInfo(event.regimentId);
                console.log(JSON.stringify(regimentInfoForView));
                expect(regimentInfoForView["1"]).to.equal(otherAccount0.address);

            });

            it("Should addAdmin correctly", async function () {
                const { regiment, owner, otherAccount0, otherAccount1 } = await loadFixture(deployRegimentFixture);
                const interface = new ethers.utils.Interface(["event RegimentCreated(uint256 create_time, address manager,address[] InitialMemberList,bytes32 regimentId)"]);
                const _manager = otherAccount0.address;
                const _initialMemberList = [otherAccount0.address, otherAccount1.address];
                const _isApproveToJoin = false;
                var tx = await regiment.CreateRegiment(_manager, _initialMemberList, _isApproveToJoin);
                const receipt = await tx.wait();

                for (const event of receipt.events) {
                    console.log(`Event ${event.event} with args ${event.args}`);
                }
                const data = receipt.logs[0].data;
                const topics = receipt.logs[0].topics;
                const event = interface.decodeEventLog("RegimentCreated", data, topics);
                var regimentId = event.regimentId;
                var _newAdmins = [owner.address];
                var originSenderAddress = otherAccount0.address;
                await regiment.AddAdmins(regimentId, _newAdmins, originSenderAddress);

                var regimentInfoForView = await regiment.GetRegimentInfo(event.regimentId);
                console.log(JSON.stringify(regimentInfoForView));
                 expect(regimentInfoForView["2"][0]).to.equal(_newAdmins[0]);
               
            });
        })
    });


});