// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
async function main() {
    console.log("Deploying contracts...");

    /////////////////////////////////////////////////////////////////////
    // Chainlink documentation: 
    // https://github.com/smartcontractkit/hardhat-starter-kit/blob/main/test/unit/RandomNumberConsumer.spec.js
    /////////////////////////////////////////////////////////////////////
  
    const BASE_FEE = "1000000000000000";                        // 0.001 ether as base fee
    const GAS_PRICE = "50000000000";                            // 50 gwei 
    const WEI_PER_UNIT_LINK = "10000000000000000";              // 0.01 ether per LINK
    const INTERVAL = 30;                                        // 30 seconds
    const CALL_BACK_GAS_LIMIT = 100000;                         // 100,000 gas limit for callback
    const GAS_LANE = "0x9fe0eebf5e446e3c998ec9bb19951541aee00bb90ea201ae456421a2ded86805"; // gas lane
    let usdcContractAddress = "0x07865c6E87B9F70255377e024ace6630C1Eaa37F";  // USDC address

    const chainId = network.config.chainId;

    const VRFCoordinatorV2_5MockFactory = await ethers.getContractFactory(
        "VRFCoordinatorV2_5Mock"
    )
    const VRFCoordinatorV2_5Mock = await VRFCoordinatorV2_5MockFactory.deploy(
        BASE_FEE,
        GAS_PRICE,
        WEI_PER_UNIT_LINK
    )

    const transaction = await VRFCoordinatorV2_5Mock.createSubscription();
    const transactionReceipt = await transaction.wait(1);
    const subscriptionId = ethers.BigNumber.from(transactionReceipt.events[0].topics[1]);
    console.log("Transaction Id:", subscriptionId.toString());
    console.log("VRFCoordinatorV2_5Mock deployed to:", VRFCoordinatorV2_5Mock.address);
    console.log("Subscription ID:", subscriptionId.toString());

    const Lottery = await ethers.getContractFactory("Lottery");
    const lottery = await Lottery.deploy(
        subscriptionId,
        GAS_LANE,
        INTERVAL,
        CALL_BACK_GAS_LIMIT,
        VRFCoordinatorV2_5Mock.address,
        usdcContractAddress
    );
    await lottery.deployed();
    console.log("Lottery deployed to:", lottery.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
  