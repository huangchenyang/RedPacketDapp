pragma solidity 0.4.24;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";


contract CaiShen is Ownable {
    struct Gift {
        bool exists;        // 0 Only true if this exists
        uint giftId;        // 1 The gift ID 可以理解为红包的ID号
        address giver;      // 2 The address of the giver
        address recipient;  // 3 The address of the recipient
        uint expiry;        // 4 The expiry datetime of the timelock as a
                            //   Unix timestamp
        uint amount;        // 5 The amount of ETH
        bool redeemed;      // 6 Whether the funds have already been redeemed？？
        string giverName;   // 7 The giver's name
        string message;     // 8 A message from the giver to the recipient
        uint timestamp;     // 9 The timestamp of when the gift was given
    }

    // Total fees gathered since the start of the contract or the last time
    // fees were collected, whichever is latest. 总的费用
    uint public feesGathered;

    // Each gift has a unique ID. If you increment this value, you will get
    // an unused gift ID.
    uint public nextGiftId;

    // Maps each recipient address to a list of giftIDs of Gifts they have
    // received. 将接收者的地址转化为接收者的Gift ID
    mapping (address => uint[]) public recipientToGiftIds;

    // Maps each gift ID to its associated gift.
    mapping (uint => Gift) public giftIdToGift;

	//定义事件
    event Constructed (address indexed by, uint indexed amount);
	//收集所有费用
    event CollectedAllFees (address indexed by, uint indexed amount);
	//给合约充值
    event DirectlyDeposited(address indexed from, uint indexed amount);
	//给
    event Gave (uint indexed giftId,
                address indexed giver,
                address indexed recipient,
                uint amount, uint expiry);
	//补偿
    event Redeemed (uint indexed giftId,
                    address indexed giver,
                    address indexed recipient,
                    uint amount);

    // Constructor
    constructor() public payable {
        Constructed(msg.sender, msg.value);
    }

    // Fallback function which allows this contract to receive funds.
    function () public payable {
        // Sending ETH directly to this contract does nothing except log an
        // event.直接向合约充值
        DirectlyDeposited(msg.sender, msg.value);
    }

    //// Getter functions:
	
	//接收者的git id
    function getGiftIdsByRecipient (address recipient) 
    public view returns (uint[]) {
        return recipientToGiftIds[recipient];
    }

    //// Contract functions: 合约相关的函数

    // Call this function while sending ETH to give a gift.
    // @recipient: the recipient's address
    // @expiry: the Unix timestamp of the expiry datetime.
    // @giverName: the name of the giver
    // @message: a personal message
    // Tested in test/test_give.js and test/TestGive.sol
    function give (address recipient, uint expiry, string giverName, string message)
    public payable returns (uint) {
        address giver = msg.sender;
		
		//对参数进行检查
        // Validate the giver address,检查地址是否有效
        assert(giver != address(0));

        // The gift must be a positive amount of ETH
        uint amount = msg.value;
        require(amount > 0);
        
        // The expiry datetime must be in the future.
        // The possible drift is only 12 minutes.
        // See: https://consensys.github.io/smart-contract-best-practices/recommendations/#timestamp-dependence
        require(expiry > now);

        // The giver and the recipient must be different addresses
        require(giver != recipient);

        // The recipient must be a valid address
        require(recipient != address(0));

        // Make sure nextGiftId is 0 or positive, or this contract is buggy
        assert(nextGiftId >= 0);

        // Calculate the contract owner's fee 计算费用
        uint feeTaken = fee(amount);
        assert(feeTaken >= 0);

        // Increment feesGathered，总费用
        feesGathered = SafeMath.add(feesGathered, feeTaken);

        // Shave off the fee from the amount，从账户中扣除费用
        uint amtGiven = SafeMath.sub(amount, feeTaken);
        assert(amtGiven > 0);

		//检查git ID 是否一样
        // If a gift with this new gift ID already exists, this contract is buggy.
        assert(giftIdToGift[nextGiftId].exists == false);

        // Update the mappings
        recipientToGiftIds[recipient].push(nextGiftId);
        giftIdToGift[nextGiftId] = 
            Gift(true, nextGiftId, giver, recipient, expiry, 
            amtGiven, false, giverName, message, now);

        uint giftId = nextGiftId;

        // Increment nextGiftId
        nextGiftId = SafeMath.add(giftId, 1);

        // If a gift with this new gift ID already exists, this contract is buggy.
        assert(giftIdToGift[nextGiftId].exists == false);

        // Log the event
        Gave(giftId, giver, recipient, amount, expiry);

        return giftId;
    }

    // Call this function to redeem a gift of ETH. 将git兑换为eth
    // Tested in test/test_redeem.js
    function redeem (uint giftId) public {
        // The giftID should be 0 or positive
        require(giftId >= 0);

        // The gift must exist and must not have already been redeemed
        require(isValidGift(giftIdToGift[giftId]));

        // The recipient must be the caller of this function
        address recipient = giftIdToGift[giftId].recipient;
        require(recipient == msg.sender);

        // The current datetime must be the same or after the expiry timestamp
        require(now >= giftIdToGift[giftId].expiry);

        //// If the following assert statements are triggered, this contract is
        //// buggy.

        // The amount must be positive because this is required in give()
        uint amount = giftIdToGift[giftId].amount;
        assert(amount > 0);

        // The giver must not be the recipient because this was asserted in give()
        address giver = giftIdToGift[giftId].giver;
        assert(giver != recipient);

        // Make sure the giver is valid because this was asserted in give();
        assert(giver != address(0));

        // Update the gift to mark it as redeemed, so that the funds cannot be
        // double-spent
        giftIdToGift[giftId].redeemed = true;

        // Transfer the funds,调用solidity中的address中的transfer
        recipient.transfer(amount);

        // Log the event
        Redeemed(giftId, giftIdToGift[giftId].giver, recipient, amount);
    }

    // Calculate the contract owner's fee
    // Tested in test/test_fee.js
    function fee (uint amount) public pure returns (uint) {
        if (amount <= 0.01 ether) {
            return 0;
        } else if (amount > 0.01 ether) {
			//除以100
            return SafeMath.div(amount, 100);
        }
    }

    // Transfer the fees collected thus far to the contract owner.
    // Only the contract owner may invoke this function.
    // Tested in test/test_collect_fees.js
    function collectAllFees () public onlyOwner {
        // Store the fee amount in a temporary variable
        uint amount = feesGathered;

        // Make sure that the amount is positive
        require(amount > 0);

        // Set the feesGathered state variable to 0
        feesGathered = 0;

        // Make the transfer
        owner.transfer(amount);

        CollectedAllFees(owner, amount);
    }

    // Returns true only if the gift exists and has not already been
    // redeemed
    function isValidGift(Gift gift) private pure returns (bool) {
        return gift.exists == true && gift.redeemed == false;
    }
}
