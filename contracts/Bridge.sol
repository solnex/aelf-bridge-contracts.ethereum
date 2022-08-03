import './MerkleTree.sol';
import './Receipts.sol';
import './Regiment.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
pragma solidity 0.8.9;

contract Bridge is Receipts, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeERC20 for IERC20;
    Merkle merkeTree;
    Regiment regiment;
    EnumerableSet.Bytes32Set private tokenList;

    uint256 public MaxReceoptViewCount = 20;
    mapping(bytes32 => SwapInfo) internal swapInfos;

    mapping(bytes32 => mapping(address => SwapPairInfo)) swapPairInfos;

    mapping(bytes32 => mapping(uint256 => SwapAmounts)) internal ledger;

    event TokenAdded(address token, string chainId);
    event TokenRemoved(address token, string chainId);
    event NewReceipt(
        uint256 receiptId,
        address asset,
        address owner,
        uint256 amount
    );
    event SwapPairAdded(bytes32);
    event TokenSwapEvent(address receiveAddress, address token, uint256 amount);

    struct SwapTargetToken {
        address token;
        SwapRatio swapRatio;
    }
    struct SwapRatio {
        uint64 originShare;
        uint64 targetShare;
    }

    struct SwapInfo {
        bytes32 swapId;
        SwapTargetToken[] swapTargetTokenList;
        bytes32 regimentId;
        bytes32 spaceId;
    }
    struct SwapPairInfo {
        uint256 swappedAmount;
        uint256 swappedTimes;
        uint256 depositAmount;
    }
    struct MerklePathInfo {
        uint256 lastLeafIndex;
        bytes32[] merkelTreePath;
        bool[] isLeftNode;
    }
    struct SwapAmounts {
        address receiver;
        mapping(address => uint256) receivedAmounts;
    }

    constructor(address _merkeTree, address _regiment) {
        merkeTree = Merkle(_merkeTree);
        regiment = Regiment(_regiment);
    }

    function addToken(address token, string calldata chainId) public {
        require(msg.sender == owner(), 'No permission. ');
        bytes32 tokenKey = _generateTokenKey(token, chainId);
        tokenList.add(tokenKey);
        emit TokenAdded(token, chainId);
    }

    function removeToken(address token, string calldata chainId) public {
        require(msg.sender == owner(), 'No permission. ');
        bytes32 tokenKey = _generateTokenKey(token, chainId);
        tokenList.add(tokenKey);
        emit TokenRemoved(token, chainId);
    }

    function _generateTokenKey(address token, string calldata chainId)
        private
        pure
        returns (bytes32)
    {
        return sha256(abi.encodePacked(token, chainId));
    }

    // Create new receipt and deposit erc20 token
    function createReceipt(
        address token,
        uint256 amount,
        string calldata targetChainId,
        string calldata targetAddress
    ) external {
        bytes32 tokenKey = _generateTokenKey(token, targetChainId);
        require(
            tokenList.contains(tokenKey),
            'Token is not support in that chain'
        );
        // Deposit token to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 receiptId = receiptCounts[token];
        receipts[token].push(
            Receipt(
                receiptId,
                token,
                msg.sender,
                targetChainId,
                targetAddress,
                amount,
                block.number,
                block.timestamp
            )
        );
        totalAmountInReceipts[token] = totalAmountInReceipts[token].add(amount);
        receiptCounts[token] = receipts[token].length;
        ownerToReceipts[msg.sender][token].push(receiptId);
        emit NewReceipt(receiptId, token, token, amount);
    }

    function getMyReceipts(address user, address token)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory receipt_ids = ownerToReceipts[user][token];
        return receipt_ids;
    }

    function getLockTokens(address user, address token)
        external
        view
        returns (uint256)
    {
        uint256[] memory myReceipts = ownerToReceipts[user][token];
        uint256 amount = 0;

        for (uint256 i = 0; i < myReceipts.length; i++) {
            amount = amount.add(receipts[token][myReceipts[i]].amount);
        }

        return amount;
    }

    function getExceptReceiptInfo(address token, uint256 index)
        public
        view
        returns (Receipt memory receipt)
    {
        return receipts[token][index];
    }

    function getReceiptInfos(address token, uint256 fromIndex)
        public
        view
        returns (Receipt[] memory _receipts)
    {
        if (receiptCounts[token] == 0) {
            return _receipts;
        }
        uint256 latesIndex = receiptCounts[token].sub(1);
        require(fromIndex <= latesIndex, 'Invalid input');
        uint256 length = latesIndex.sub(fromIndex).add(1);
        length = length > MaxReceoptViewCount ? MaxReceoptViewCount : length;
        _receipts = new Receipt[](length);
        uint256 currentIndex = fromIndex;
        for (uint256 i = 0; i < length; i++) {
            _receipts[i] = receipts[token][currentIndex];
            currentIndex++;
        }
        return _receipts;
    }

    function getReceivedReceiptInfos(address token, uint256 fromIndex)
        public
        view
        returns (ReceivedReceipt[] memory _receipts)
    {
        uint256 count = receivedReceipts[token].length;
        if (count == 0) {
            return _receipts;
        }
        uint256 latesIndex = count.sub(1);
        require(fromIndex <= latesIndex, 'Invalid input');
        uint256 length = latesIndex.sub(fromIndex).add(1);
        length = length > MaxReceoptViewCount ? MaxReceoptViewCount : length;
        _receipts = new ReceivedReceipt[](length);
        uint256 currentIndex = fromIndex;
        for (uint256 i = 0; i < length; i++) {
            _receipts[i] = receivedReceipts[token][currentIndex];
            currentIndex++;
        }
        return _receipts;
    }

    //Swap
    function createSwap(
        SwapTargetToken[] calldata targetTokens,
        bytes32 regimentId
    ) external {
        bytes32 spaceId = merkeTree.createSpace(regimentId);
        bytes32 swapHashId = keccak256(msg.data);
        swapInfos[swapHashId].regimentId = regimentId;
        swapInfos[swapHashId].spaceId = spaceId;
        swapInfos[swapHashId].swapId = swapHashId;

        for (uint256 i = 0; i < targetTokens.length; i++) {
            validtateSwapRatio(targetTokens[i].swapRatio);
            swapInfos[swapHashId].swapTargetTokenList.push(targetTokens[i]);
        }
        emit SwapPairAdded(swapHashId);
    }

    function validtateSwapRatio(SwapRatio memory _swapRatio) private pure {
        require(
            _swapRatio.originShare > 0 && _swapRatio.targetShare > 0,
            'invalid swap ratio'
        );
    }

    function deposit(
        bytes32 swapHashId,
        address[] memory tokens,
        uint256[] memory amounts
    ) external {
        SwapInfo storage swapInfo = swapInfos[swapHashId];
        bool isManager = regiment.IsRegimentManager(
            swapInfo.regimentId,
            msg.sender
        );
        require(isManager, 'No permission. ');
        require(
            tokens.length == amounts.length,
            'Invalid tokens/amounts input'
        );
        SwapTargetToken[] memory swapTargetTokenList = swapInfo
            .swapTargetTokenList;
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenVerify(tokens[i], swapTargetTokenList);
            IERC20(tokens[i]).safeTransferFrom(
                address(msg.sender),
                address(this),
                amounts[i]
            );
            swapPairInfos[swapHashId][tokens[i]].depositAmount = swapPairInfos[
                swapHashId
            ][tokens[i]].depositAmount.add(amounts[i]);
        }
    }

    function withdraw(
        bytes32 swapHashId,
        address[] memory tokens,
        uint256[] memory amounts
    ) external {
        SwapInfo storage swapInfo = swapInfos[swapHashId];
        bool isManager = regiment.IsRegimentManager(
            swapInfo.regimentId,
            msg.sender
        );
        require(isManager, 'No permission. ');
        require(
            tokens.length == amounts.length,
            'Invalid tokens/amounts input'
        );
        SwapTargetToken[] memory swapTargetTokenList = swapInfo
            .swapTargetTokenList;
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenVerify(tokens[i], swapTargetTokenList);
            swapPairInfos[swapHashId][tokens[i]].depositAmount = swapPairInfos[
                swapHashId
            ][tokens[i]].depositAmount.sub(amounts[i]);
            IERC20(tokens[i]).safeTransfer(address(msg.sender), amounts[i]);
        }
    }

    function swapToken(
        bytes32 swapId,
        string memory fromChainId,
        uint256 receiptId,
        uint256 amount,
        address receiverAddress,
        MerklePathInfo calldata merklePathInfo
    ) external {
        require(
            msg.sender == receiverAddress,
            'only receiver has permission to swap token'
        );
        bytes32 spaceId = swapInfos[swapId].spaceId;
        require(spaceId != bytes32(0), 'token swap pair not found');
        require(amount > 0, 'invalid amount');
        SwapAmounts storage swapAmouts = ledger[swapId][receiptId];
        require(swapAmouts.receiver == address(0), 'already claimed');
        SwapInfo storage swapInfo = swapInfos[swapId];
        address targetToken = swapInfo.swapTargetTokenList[0].token;
        require(
            merkeTree.merkleProof(
                spaceId,
                merkeTree.getLeafLocatedMerkleTreeIndex(spaceId, receiptId),
                computeLeafHash(
                    fromChainId,
                    receiptId,
                    targetToken,
                    amount,
                    receiverAddress
                ),
                merklePathInfo.merkelTreePath,
                merklePathInfo.isLeftNode
            ),
            'failed to swap token'
        );

        swapAmouts.receiver = receiverAddress;
        SwapTargetToken[] memory swapTargetTokenList = swapInfo
            .swapTargetTokenList;

        for (uint256 i = 0; i < swapTargetTokenList.length; i++) {
            address token = swapInfo.swapTargetTokenList[i].token;
            SwapPairInfo storage swapPairInfo = swapPairInfos[swapId][token];
            uint256 targetTokenAmount = amount
                .mul(swapTargetTokenList[i].swapRatio.targetShare)
                .div(swapTargetTokenList[i].swapRatio.originShare);
            require(
                targetTokenAmount <= swapPairInfo.depositAmount,
                'deposit not enought'
            );
            swapPairInfo.swappedAmount = swapPairInfo.swappedAmount.add(
                targetTokenAmount
            );
            swapPairInfo.swappedTimes = swapPairInfo.swappedTimes.add(1);
            swapPairInfo.depositAmount = swapPairInfo.depositAmount.sub(
                targetTokenAmount
            );
            IERC20(token).transfer(receiverAddress, targetTokenAmount);
            emit TokenSwapEvent(receiverAddress, token, targetTokenAmount);
            swapAmouts.receivedAmounts[token] = targetTokenAmount;
        }

        receivedReceipts[targetToken].push(
            ReceivedReceipt(
                receiptId,
                targetToken,
                fromChainId,
                receiverAddress,
                amount,
                block.number,
                block.timestamp
            )
        );
    }

    function transmit(
        bytes calldata _report,
        bytes32[] calldata _rs, // observer的signatures的r数组
        bytes32[] calldata _ss, //observer的signatures的s数组
        bytes32 _rawVs // signatures的v 每个1字节 合到一个32字节里面 也就是最多observer签名数量为32
    ) external {
        bytes32 message = keccak256(_report);

        for (uint256 i = 0; i < _rs.length; i++) {
            address signer = ecrecover(
                message,
                uint8(_rawVs[i]) + 27,
                _rs[i],
                _ss[i]
            );
            // regiment.IsRegimentMember();
        }
    }

    function computeLeafHash(
        string memory _fromChainId,
        uint256 _receiptId,
        address _token,
        uint256 _amount,
        address _receiverAddress
    ) public pure returns (bytes32 _leafHash) {
        bytes32 _fromChainIdHash = sha256(abi.encodePacked(_fromChainId));
        bytes32 _receiptIdHash = sha256(abi.encodePacked(_receiptId));
        bytes32 _hashFromToken = sha256(abi.encodePacked(_token));
        bytes32 _hashFromAmount = sha256(abi.encodePacked(_amount));
        bytes32 _hashFromAddress = sha256(abi.encodePacked(_receiverAddress));
        _leafHash = sha256(
            abi.encode(
                _fromChainIdHash,
                _receiptIdHash,
                _hashFromToken,
                _hashFromAmount,
                _hashFromAddress
            )
        );
    }

    function tokenVerify(
        address token,
        SwapTargetToken[] memory swapTargetTokenList
    ) private pure returns (bool) {
        for (uint256 i = 0; i < swapTargetTokenList.length; i++) {
            if (swapTargetTokenList[i].token == token) {
                return true;
            }
        }
        return false;
    }
}
