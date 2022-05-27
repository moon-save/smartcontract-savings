// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract SavingsLottery is VRFConsumerBase {

    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter private lotteryId;
    mapping(uint256 => Lottery) private lotteries;
    mapping(bytes32 => uint256) private lotteryRandomnessRequest;
    mapping(uint256 => mapping(address => uint256)) ppplayer; // participations per player per lottery
    mapping(uint256 => uint256) playersCount;
    bytes32 private keyHash;
    uint256 private fee;
    address private admin;

    event RandomnessRequested(bytes32 requestId,uint256);
    event WinnerDeclared(bytes32,uint256,address[]);
    event PrizeIncreased(uint256,uint256);
    event LotteryCreated(uint256,uint256,uint256,uint256);

    struct Lottery {
        uint256 lotteryId;
        address[] participants;
        uint256 ticketPrice;
        uint256 prize;
        address[] winners;
        bool isFinished;
        uint endDate;
    }

    constructor(address vrfCoordinator, address link, bytes32 _keyhash, uint256 _fee) 
    VRFConsumerBase(vrfCoordinator, link)
    {
        keyHash = _keyhash;
        fee = _fee;
        admin = msg.sender;
    }

    function createLottery(uint256 _ticketPrice, uint256 _seconds) payable public onlyAdmin {
        require(_ticketPrice > 0, "Value must be greater than 0");
        Lottery memory lottery = Lottery({
            lotteryId: lotteryId.current(),
            participants: new address[](0),
            prize: 0,
            ticketPrice: _ticketPrice,
            winners: new address[](4),
            isFinished: false,
            endDate: block.timestamp + _seconds * 1 seconds
        });
        lotteries[lotteryId.current()] = lottery;
        
        emit LotteryCreated(lottery.lotteryId,lottery.ticketPrice,lottery.prize,lottery.endDate);
    }

    function depositSavings(uint256 _lotteryId) public payable {
        Lottery storage lottery = lotteries[_lotteryId];
        require(block.timestamp < lottery.endDate, "Lottery participation is closed");
        require(msg.value >= lottery.ticketPrice, "Value must be at least ticket price");

        uint256 numTickets = msg.value / lottery.ticketPrice;

        // Add tickets for the participant
        for(uint i = 0;i < numTickets; i++) {
            lottery.participants.push(msg.sender);
        }

        uint256 uniqueP = ppplayer[_lotteryId][msg.sender];

        if (uniqueP == 0) {
            playersCount[_lotteryId]++;
        }
        ppplayer[_lotteryId][msg.sender] += numTickets;
    }

    function depositInterest() public payable {
        Lottery storage lottery = lotteries[lotteryId.current()];

        lottery.prize += msg.value;
        
        emit PrizeIncreased(lottery.lotteryId, lottery.prize);
    }

    function declareWinner(uint256 _lotteryId) public onlyAdmin {
        Lottery storage lottery = lotteries[_lotteryId];
        require(block.timestamp > lottery.endDate,"Lottery is still active");
        require(!lottery.isFinished,"Lottery has already declared a winner");

        if (playersCount[_lotteryId] == 1) {
            require(lottery.participants[0] != address(0), "There has been no participation in this lottery");
            // Ditribute funds to single winner
        } else {
            require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
            bytes32 requestId = requestRandomness(keyHash, fee);
            lotteryRandomnessRequest[requestId] = _lotteryId;
            emit RandomnessRequested(requestId, _lotteryId);
        }
        lotteryId.increment();
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint256 _lotteryId = lotteryRandomnessRequest[requestId];
        Lottery storage lottery = lotteries[_lotteryId];

        uint8 numWinners = 4;
        uint256 prizeMoney = lottery.prize / numWinners;
        uint256[] memory randomWinners = expandRandomNumbers(randomness, numWinners);
        
        for (uint i = 0; i < numWinners; i++) {
            uint256 winningIndex = randomWinners[i].mod(lottery.participants.length);
            lottery.winners[i] = lottery.participants[winningIndex];
            lottery.winners[i].call{value: prizeMoney}("");
        }

        lottery.isFinished = true;

        delete lotteryRandomnessRequest[requestId];
        delete playersCount[_lotteryId];
        
        emit WinnerDeclared(requestId, lottery.lotteryId, lottery.winners);
    }

    function getLottery(uint256 _lotteryId) public view returns (Lottery memory) {
        return lotteries[_lotteryId];
    }

    function getLotteryID() public view returns(uint256) {
        return lotteryId.current();
    }

    function getPlayersCount() public view returns(uint256) {
        return playersCount[lotteryId.current()];
    }

    function getWinners() public view returns(address[] memory) {
        return lotteries[lotteryId.current()-1].winners;
    }

    function getInterestPool() public view returns(uint256) {
        return lotteries[lotteryId.current()].prize;
    }

    function getPlayerBalance() public view returns(uint256) {
        Lottery storage lottery = lotteries[lotteryId.current()];
        return ppplayer[lotteryId.current()][msg.sender] * lottery.ticketPrice;
    }
    
    function expandRandomNumbers(uint256 randomValue, uint256 n) public pure returns (uint256[] memory expandedValues) {
        expandedValues = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            expandedValues[i] = uint256(keccak256(abi.encode(randomValue, i)));
        }
        return expandedValues;
    }

    modifier onlyAdmin {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }
}
