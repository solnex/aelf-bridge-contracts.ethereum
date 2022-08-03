const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
describe("MerkleTree", function () {
    async function deployRegimentFixture() {
        // Contracts are deployed using the first signer/account by default
        const _memberJoinLimit = 10;
        const _regimentLimit = 20;
        const _maximumAdminsCount = 5;

        const [owner] = await ethers.getSigners();
        const Regiment = await ethers.getContractFactory("Regiment");
        const regiment = await Regiment.deploy(_memberJoinLimit, _regimentLimit, _maximumAdminsCount);
        const _manager = owner.address;
        const _initialMemberList = [owner.address];
        const _isApproveToJoin = false;
        var tx = await regiment.CreateRegiment(_manager, _initialMemberList, _isApproveToJoin);
        const receipt = await tx.wait();
        const data = receipt.logs[0].data;
        const topics = receipt.logs[0].topics;
        const event = interface.decodeEventLog("RegimentCreated", data, topics);
        var regimentId = event.regimentId;
        var _newAdmins = [owner.address];
        var originSenderAddress = owner.address;
        await regiment.AddAdmins(regimentId, _newAdmins, originSenderAddress);

        return { regiment, owner, regimentId };
    }
    async function deployMerkleTreeFixture() {
        // Contracts are deployed using the first signer/account by default

        const { regiment, owner, regimentId } = await loadFixture(deployRegimentFixture);
        const MerkleTree = await ethers.getContractFactory("MerkleTree");
        const merkleTree = await MerkleTree.deploy(regiment.address);
        return { merkleTree, owner, regimentId };
    }
    describe("action function test", function () {
        describe("create space test", function () {
            it("Should create correctly", async function () {
                const { merkleTree, owner, regimentId } = await loadFixture(deployMerkleTreeFixture);
                await merkleTree.createSpace(regimentId);
            });
        })
    });

});