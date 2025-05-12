// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

error NotEnoughMoney();
error NotEnoughTickets();
error NotEnoughFunds();
error NoWinnerFound();
error NoRandomNumbersReturned();
error LotteryNotOpen();
error NotValidCall();

// Abstract
interface USDC {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Lottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {

    enum LotteryState {
        OPEN,
        DRAWING
    }

    /* ######### */
    /* Variables */
    /* ######### */
    uint        private constant TICKET_PRICE_USDT = 1;             //ticket price in USDC
    uint256     private constant PERCENTAGE = 15;                   //fixed percentage that will be paid out to manager when a winning draw occurs

    USDC        private usdcToken;
    address     private manager;                                    //address of the manager
    address     payable[] private currentDrawingParticipants;       //this will contain all addresses for the current draw
    address[]   private drawingWinners;                             //winners of the draw
    uint256     private drawingNumber;                              //current drawing number
    uint8[]     private numbersSelected;                            //store 5 unique numbers between 1–60 for the draw
    LotteryState private lotteryState;    

    mapping(address => mapping(uint256 => uint256[]))   private participantsNumbers;
    mapping(address => uint256)                         private participantTicketCount;
    mapping(uint256 => address[])                       private historicalDrawingWinners;

    /* ####################### */
    /* Chainlink VRF Variables */
    /* ####################### */
    uint16      private constant REQUEST_CONFIRMATIONS = 3;
    uint32      private constant NUM_WORDS = 5;    
    uint256     private immutable i_subscriptionId;
    bytes32     private immutable i_keyHash;
    uint32      private immutable i_callbackGasLimit;
    uint256     private immutable i_interval;
    uint256     private lastTimeStamp;   

    uint256[] public s_randomWords;
    uint256 public s_requestId; 

    /**
     * HARDCODED FOR SEPOLIA
     * COORDINATOR: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B
     */

    /* ###### */
    /* Events */
    /* ###### */
    event DrawingEntered(uint256 drawingNumber, address ticketOwner, uint256 num1, uint256 num2, uint256 num3, uint256 num4, uint256 num5);
    event DrawingWinner(uint256 indexed drawingNumber, address indexed winner);
    event WinnerPaid(uint256 indexed drawingNumber, address indexed paidWinner);
    event RequestSent(uint256 requestId, uint256 timestamp);

    event ReturnedRandomness(uint256[] randomWords);            

    /* ######### */
    /* Functions */
    /* ######### */
    constructor(
        uint256 subscriptionId,
        bytes32 keyHash, // keyHash
        uint256 interval,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2,
        address usdcTokenAddress
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        i_keyHash = keyHash;
        i_interval = interval;
        i_subscriptionId = subscriptionId;        
        i_callbackGasLimit = callbackGasLimit;
        lastTimeStamp = block.timestamp;

        manager = payable(msg.sender);
        usdcToken = USDC(usdcTokenAddress);
        drawingNumber = 1;        
        lotteryState = LotteryState.OPEN;
    }

    function enterDrawing(uint256 numTickets, uint256[] memory num1, 
                            uint256[] memory num2, uint256[] memory num3, 
                            uint256[] memory num4, uint256[] memory num5) public payable {

        if(lotteryState != LotteryState.OPEN) {
            revert LotteryNotOpen();
        }

        uint256 amount = (TICKET_PRICE_USDT * 1e6) * numTickets; //convert to USDC

        // Transfer money from user to this contract
        bool isTransferSuccessfull = usdcToken.transferFrom(msg.sender, address(this), amount); 

        if(isTransferSuccessfull) { 
            for (uint256 i = 0; i < numTickets; i++) {
                currentDrawingParticipants.push(payable(msg.sender));

                uint256[] memory numbers = new uint256[](5);
                numbers[0] = num1[i];
                numbers[1] = num2[i];
                numbers[2] = num3[i];
                numbers[3] = num4[i];
                numbers[4] = num5[i];

                participantsNumbers[msg.sender][participantTicketCount[msg.sender]] = numbers;
                participantTicketCount[msg.sender] += 1;

                // emit event to record participant into the blockchain
                emit DrawingEntered(drawingNumber, msg.sender, num1[i], num2[i], num3[i], num4[i], num5[i]);
            }       
        } else {
            revert NotEnoughMoney();
        }
    }
    
    /* ################### */
    /* CHAINLINK FUNCTIONS */
    /* ################### */
    // -> https://docs.chain.link/chainlink-automation/guides/compatible-contracts
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPassed = ((block.timestamp - lastTimeStamp) > i_interval);
        bool hasPlayers = (currentDrawingParticipants.length > 0);
        bool hasBalance = (address(this).balance > 0);
        bool isOpen = (lotteryState == LotteryState.OPEN);
        upkeepNeeded = timeHasPassed && hasPlayers && hasBalance && isOpen;
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert NotValidCall();
        }

        // Will revert if subscription is not set and funded.
        // -> https://docs.chain.link/vrf/v2-5/subscription/get-a-random-number
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        emit RequestSent(requestId, block.timestamp);
    }

    function requestRandomWords() external onlyOwner {
        s_requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        emit RequestSent(s_requestId, block.timestamp);
    }

    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override {
        emit ReturnedRandomness(randomWords);
        numbersSelected = getUniqueNumbersFromVRF(randomWords, 60, 5);
        findWinners();
    }

    function getUniqueNumbersFromVRF(uint256[] memory randomWords, uint8 max, uint8 count) internal pure returns (uint8[] memory) {
        if(count <= max) {
            revert NoRandomNumbersReturned();
        }

        uint8[] memory selected = new uint8[](count);
        bool[] memory seen = new bool[](max + 1);
        uint8 filled = 0;
        uint256 i = 0;

        while (filled < count) {
            uint8 num = uint8((randomWords[i % randomWords.length] + i) % max + 1);
            if (!seen[num]) {
                seen[num] = true;
                selected[filled] = num;
                filled++;
            }
            i++;
        }
        return selected;
    }

    /* ################# */
    /* PRIVATE FUNCTIONS */
    /* ################# */
    function findWinners() private {
        lotteryState = LotteryState.DRAWING;

        (uint256 winNum1, uint256 winNum2, uint256 winNum3, uint256 winNum4, uint256 winNum5) = getWinnerNumbers();

        for (uint256 i = 0; i < currentDrawingParticipants.length; ++i) {
            address participant = currentDrawingParticipants[i];

            for (uint256 ticketIndex = 0; ticketIndex < participantTicketCount[participant]; ++ticketIndex) {
                uint256[] memory ticketNumbers = participantsNumbers[participant][ticketIndex];
                uint256 pNum1 = ticketNumbers[0];
                uint256 pNum2 = ticketNumbers[1];
                uint256 pNum3 = ticketNumbers[2];
                uint256 pNum4 = ticketNumbers[3];
                uint256 pNum5 = ticketNumbers[4];

                if (winNum1 == pNum1 && winNum2 == pNum2 && winNum3 == pNum3 && winNum4 == pNum4 && winNum5 == pNum5) {
                    drawingWinners.push(participant);
                    emit DrawingWinner(drawingNumber, participant);
                }
            }
        }

        if (drawingWinners.length > 0) {
            historicalDrawingWinners[drawingNumber] = drawingWinners;
            if (payWinners()) {
                //reset winners for next draw
                drawingWinners = new address[](0);
            }
        }

        drawingNumber++;
        //reset current drawing participants
        currentDrawingParticipants = new address payable[](0);
        lotteryState = LotteryState.OPEN;
    }

    function payWinners() private returns (bool) {
        uint256 amountToManager = (address(this).balance * PERCENTAGE) / 100;
        uint256 amountToWinners = address(this).balance - amountToManager;
        uint256 amountToIndividualWinner = amountToWinners / drawingWinners.length;

        //Pay manager
        // (bool callManagerSucess, ) = address(this).call{value: amountToManager}("");
        // require(callManagerSucess, "Withdrawal failed!");
        usdcToken.transfer(manager, amountToManager);

        //Pay winners
        for (uint256 i = 0; i < drawingWinners.length; ++i) {
            //(bool callSucess, ) = drawingWinners[i].call{ value: amountToIndividualWinner }("");
            //require(callSucess, "Withdrawal failed!");
            usdcToken.transfer(drawingWinners[i], amountToIndividualWinner);

            emit WinnerPaid(drawingNumber, drawingWinners[i]);
        }

        return true;
    }
    
    function getWinnerNumbers() private view returns (uint8, uint8, uint8, uint8, uint8) {        
        return (numbersSelected[0], numbersSelected[1], numbersSelected[2], numbersSelected[3], numbersSelected[4]); //for testing purposes
    }

    /* ################# */
    /* GET FUNCTIONS */
    /* ################# */
    function getLatestDrawingNumbers() public view returns(uint8[] memory) {
        return numbersSelected;
    }

    function getCurrentDrawingNumber() public view returns(uint256) {
        return drawingNumber;
    }

    function getAllWinnersFromDrawing(uint256 _drawingNumber) public view returns(address[] memory) {        
        return historicalDrawingWinners[_drawingNumber];
    }
}
