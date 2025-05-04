// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

error OnlyManager();
error NotEnoughMoney();

// Abstract
interface USDC {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Lottery {
    USDC        public usdcToken;
    address     payable public immutable manager;               //this is the address of our contract owner, we use it as an alias for “owner”
    address     payable[] public currentDrawingParticipants;    //this will contain all addresses for the current draw
    uint256     public currentDrawingTotalAmount;               //total $ amount collected for current draw
    uint        public constant TICKET_PRICE_USDT = 1;          //ticket price in USDC
    uint256     public constant PERCENTAGE = 15;                //fixed percentage that will be paid out to manager when a winning draw occurs
    address[]   private drawingWinners;                         //winners of the draw
    uint256     public drawingNumber;                           //current drawing number

    mapping(address => mapping(uint256 => uint256[]))   public participantsNumbers;
    mapping(address => uint256)                         public participantTicketCount;
    mapping(address => uint256)                         public historicalDrawingWinners;

    /* EVENTS */
    event DrawingEntered(uint256, address, uint256, uint256, uint256, uint256, uint256); //(drawingNumber, msg.sender, num1, num2, num3, num4, num5)
    event DrawingWinner(uint256, address);                      //record winner
    event WinningPaid(uint256, address);                        //record winning payment

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert OnlyManager();
        }
        _;
    }

    constructor(address _usdcTokenAddress) {
        usdcToken = USDC(_usdcTokenAddress);
        manager = payable(msg.sender);
        drawingNumber = 1;
    }

    function enterDrawing(uint256 numTickets, uint256[] memory _num1, 
                            uint256[] memory _num2, uint256[] memory _num3, 
                            uint256[] memory _num4, uint256[] memory _num5) public payable {

        uint256 amount = (TICKET_PRICE_USDT * 1e6) * numTickets; //convert to USDC

        if (msg.value < amount) {
            revert NotEnoughMoney();
        }

        // Transfer money to this contract
        usdcToken.transferFrom(msg.sender, address(this), amount);  
 
        for (uint256 i = 0; i < numTickets; i++) {
            currentDrawingParticipants.push(payable(msg.sender));
            currentDrawingTotalAmount += amount;

            uint256[] memory numbers = new uint256[](5);
            numbers[0] = _num1[i];
            numbers[1] = _num2[i];
            numbers[2] = _num3[i];
            numbers[3] = _num4[i];
            numbers[4] = _num5[i];

            participantsNumbers[msg.sender][participantTicketCount[msg.sender]] = numbers;
            participantTicketCount[msg.sender] += 1;

            // emit event to record participant into the blockchain
            emit DrawingEntered(drawingNumber, msg.sender, _num1[i], _num2[i], _num3[i], _num4[i], _num5[i]);
        }       
    }

    function runDrawing() public payable onlyManager {
        payOracleSubscriptionToRunDrawing();

        findWinners();

        if (drawingWinners.length > 0) {
            if (payWinners()) {
                //reset winners for next draw
                drawingWinners = new address[](0);
            }
        }

        drawingNumber++;
        //reset current drawing participants
        currentDrawingParticipants = new address payable[](0);
    }

    function findWinners() private {
        (uint256 winNum1, uint256 winNum2, uint256 winNum3, uint256 winNum4, uint256 winNum5) = getWinningNumbers();

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
                    //add winner to historical mapping
                    historicalDrawingWinners[participant] = drawingNumber;

                    emit DrawingWinner(drawingNumber, participant);
                }
            }
        }
    }

    function payOracleSubscriptionToRunDrawing() private {
        currentDrawingTotalAmount = currentDrawingTotalAmount - TICKET_PRICE_USDT;

        //pay oracle subscription
        //CODE
    }

    function getWinningNumbers() private pure returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (5, 10, 18, 30, 60);
    }

    function payWinners() private returns (bool) {
        uint256 amountToManager = (currentDrawingTotalAmount * PERCENTAGE) / 100;
        uint256 amountToWinners = currentDrawingTotalAmount - amountToManager;
        uint256 amountToIndividualWinner = amountToWinners / drawingWinners.length;

        //Pay manager
        (bool callManagerSucess, ) = manager.call{value: amountToManager}("");
        require(callManagerSucess, "Withdrawal failed!");

        //Pay winners
        for (uint256 i = 0; i < drawingWinners.length; ++i) {
            //(bool callSucess, ) = drawingWinners[i].call{ value: amountToIndividualWinner }("");
            //require(callSucess, "Withdrawal failed!");
            usdcToken.transfer(drawingWinners[i], amountToIndividualWinner);

            emit WinningPaid(drawingNumber, drawingWinners[i]);
        }

        return true;
    }
}
