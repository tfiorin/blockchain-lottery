const { expect } = require("chai");

describe("Lottery", () => {

    let lottery, owner, addr1, addr2, addrs;

    before(async () => {
        // Deploy the DateUtils contract first
        const Lottery = await hre.ethers.getContractFactory("Lottery");
        lottery = await Lottery.deploy("PARAMETERS");
        await lottery.deployed();

        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    });

    describe("Deployment", () => {  
        it("should set the right owner", async () => {
            const _owner = await lottery.owner();
            expect(_owner).to.equal(owner.address);
        });
    });
});