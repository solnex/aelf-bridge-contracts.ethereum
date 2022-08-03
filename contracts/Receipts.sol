pragma solidity 0.8.9;

contract Receipts {
    struct Receipt {
        uint256 receiptId;
        address asset; // ERC20 Token Address
        address owner; // Sender
        string targetChainId;
        string targetAddress; // User address in aelf
        uint256 amount; // Locking amount
        uint256 blockHeight;
        uint256 blockTime;
    }

    struct ReceivedReceipt {
        uint256 receiptId;
        address asset; // ERC20 Token Address
        string fromChainId;
        address targetAddress; // User address in aelf
        uint256 amount; // Locking amount
        uint256 blockHeight;
        uint256 blockTime;
    }

    mapping(address => uint256) public receiptCounts;
    mapping(address => Receipt[]) public receipts;
    mapping(address => uint256) public totalAmountInReceipts;

    mapping(address => mapping(address => uint256[])) public ownerToReceipts;

    mapping(address => ReceivedReceipt[]) receivedReceipts;
}
