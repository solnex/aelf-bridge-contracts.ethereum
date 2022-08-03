import './Regiment.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
pragma solidity 0.8.9;

contract Merkle {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint256 constant pathMaximalLength = 10;
    uint256 public constant MerkleTreeMaximalLeafCount = 1 << pathMaximalLength;
    uint256 constant TreeMaximalSize = MerkleTreeMaximalLeafCount * 2;
    struct SpaceInfo {
        uint256 maxLeafCount;
        bytes32 operator;
    }
    struct MerkleTree {
        bytes32 spaceId;
        uint256 merkleTreeIndex;
        uint256 firstLeafIndex;
        uint256 lastLeafIndex;
        bytes32 merkleTreeRoot;
        bool isFullTree;
    }

    address public regimentAddress;

    mapping(bytes32 => SpaceInfo) private spaceInfoMap;

    mapping(bytes32 => uint256) private RegimentSpaceIndexMap;

    mapping(bytes32 => EnumerableSet.Bytes32Set) private RegimentSpaceIdListMap;

    mapping(bytes32 => mapping(uint256 => MerkleTree)) private SpaceMerkleTree;

    mapping(bytes32 => uint256) private FullMerkleTreeCountMap;

    mapping(bytes32 => uint256) private LastRecordedMerkleTreeIndex;

    mapping(bytes32 => mapping(uint256 => EnumerableSet.Bytes32Set))
        private treeLeafList;

    event SpaceCreated(
        bytes32 regimentId,
        bytes32 spaceId,
        SpaceInfo spaceInfo
    );
    event MerkleTreeRecorded(
        bytes32 regimentId,
        bytes32 spaceId,
        uint256 merkleTreeIndex,
        uint256 lastRecordedLeafIndex
    );

    constructor(address _regimentAddress) {
        regimentAddress = _regimentAddress;
    }

    function createSpace(bytes32 regimentId) external returns (bytes32) {
        bool isAdmin = Regiment(regimentAddress).IsRegimentAdmin(
            regimentId,
            msg.sender
        );
        require(isAdmin, 'No permission.');

        uint256 spaceIndex = RegimentSpaceIndexMap[regimentId];
        bytes32 spaceId = sha256(abi.encodePacked(regimentId, spaceIndex));

        spaceInfoMap[spaceId] = SpaceInfo({
            maxLeafCount: MerkleTreeMaximalLeafCount,
            operator: regimentId
        });
        RegimentSpaceIndexMap[regimentId] = spaceIndex.add(1);
        RegimentSpaceIdListMap[regimentId].add(spaceId);

        emit SpaceCreated(regimentId, spaceId, spaceInfoMap[spaceId]);
        return spaceId;
    }

    function recordMerkleTree(bytes32 spaceId, bytes32[] memory leafNodeHash)
        external
    {
        SpaceInfo storage spaceInfo = spaceInfoMap[spaceId];
        address[] memory memberList = Regiment(regimentAddress)
            .GetRegimentMemberList(spaceInfo.operator);
        require(contains(msg.sender, memberList), 'No permission.');
        uint256 lastRecordedMerkleTreeIndex = LastRecordedMerkleTreeIndex[
            spaceId
        ];

        uint256 expectIndex = saveLeaves(spaceId, leafNodeHash);

        for (
            ;
            lastRecordedMerkleTreeIndex <= expectIndex;
            lastRecordedMerkleTreeIndex++
        ) {
            updateMerkleTree(spaceId, lastRecordedMerkleTreeIndex);
        }
    }

    function getSpaceInfo(bytes32 spaceId)
        public
        view
        returns (SpaceInfo memory)
    {
        return spaceInfoMap[spaceId];
    }

    function contains(address checkAddress, address[] memory checkList)
        private
        pure
        returns (bool)
    {
        for (uint256 i; i < checkList.length; i++) {
            if (checkList[i] == checkAddress) {
                return true;
            }
        }
        return false;
    }

    function saveLeaves(bytes32 spaceId, bytes32[] memory leafNodeHash)
        private
        returns (uint256)
    {
        uint256 savedLeafsCount = 0;
        uint256 currentTreeIndex = LastRecordedMerkleTreeIndex[spaceId];
        uint256 remainLeafCount;
        while (savedLeafsCount < leafNodeHash.length) {
            remainLeafCount = getRemainLeafCountForExactTree(
                spaceId,
                currentTreeIndex
            );
            uint256 restLeafCount = leafNodeHash.length.sub(savedLeafsCount);
            uint256 currentSaveCount = remainLeafCount >= restLeafCount
                ? restLeafCount
                : remainLeafCount;
            saveLeavesForExactTree(
                spaceId,
                currentTreeIndex,
                leafNodeHash,
                savedLeafsCount,
                savedLeafsCount.add(currentSaveCount).sub(1)
            );
            currentTreeIndex = currentTreeIndex.add(1);
            savedLeafsCount = savedLeafsCount.add(currentSaveCount);
        }
        return currentTreeIndex;
    }

    function saveLeavesForExactTree(
        bytes32 spaceId,
        uint256 treeIndex,
        bytes32[] memory leafNodeHash,
        uint256 from,
        uint256 to
    ) private {
        EnumerableSet.Bytes32Set storage leafs = treeLeafList[spaceId][
            treeIndex
        ];
        for (uint256 i = from; i <= to; i++) {
            leafs.add(leafNodeHash[i]);
        }
    }

    function updateMerkleTree(bytes32 spaceId, uint256 treeIndex) private {
        (MerkleTree memory tree, ) = _generateMerkleTree(spaceId, treeIndex);
        SpaceInfo storage spaceInfo = spaceInfoMap[spaceId];
        SpaceMerkleTree[spaceId][treeIndex] = tree;
        if (tree.isFullTree) {
            FullMerkleTreeCountMap[spaceId] = FullMerkleTreeCountMap[spaceId]
                .add(1);
        }
        LastRecordedMerkleTreeIndex[spaceId] = treeIndex;
        emit MerkleTreeRecorded(
            spaceInfo.operator,
            spaceId,
            treeIndex,
            tree.lastLeafIndex
        );
    }

    function getRemainLeafCount(bytes32 spaceId) public view returns (uint256) {
        uint256 defaultIndex = LastRecordedMerkleTreeIndex[spaceId];
        return getRemainLeafCountForExactTree(spaceId, defaultIndex);
    }

    function getRemainLeafCountForExactTree(bytes32 spaceId, uint256 treeIndex)
        public
        view
        returns (uint256)
    {
        {
            SpaceInfo storage spaceInfo = spaceInfoMap[spaceId];
            MerkleTree storage tree = SpaceMerkleTree[spaceId][treeIndex];
            if (tree.spaceId == bytes32(0)) {
                return spaceInfo.maxLeafCount;
            }
            if (tree.isFullTree) {
                return 0;
            } else {
                uint256 currentTreeCount = tree
                    .lastLeafIndex
                    .sub(tree.firstLeafIndex)
                    .add(1);
                return spaceInfo.maxLeafCount.sub(currentTreeCount);
            }
        }
    }

    function getLeafLocatedMerkleTreeIndex(bytes32 spaceId, uint256 leaf_index)
        public
        view
        returns (uint256)
    {
        uint256 index = LastRecordedMerkleTreeIndex[spaceId];
        MerkleTree storage tree = SpaceMerkleTree[spaceId][index];
        uint256 lastRecordLeafIndex = tree.lastLeafIndex.sub(1);
        require(lastRecordLeafIndex >= leaf_index, 'not recorded yet');
        SpaceInfo storage spaceInfo = spaceInfoMap[spaceId];
        uint256 merkleTreeIndex = leaf_index.div(spaceInfo.maxLeafCount);
        return merkleTreeIndex;
    }

    function getFullTreeCount(bytes32 spaceId) public view returns (uint256) {
        return FullMerkleTreeCountMap[spaceId];
    }

    function getLastLeafIndex(bytes32 spaceId) public view returns (uint256) {
        uint256 index = LastRecordedMerkleTreeIndex[spaceId];
        MerkleTree storage tree = SpaceMerkleTree[spaceId][index];
        return tree.lastLeafIndex;
    }

    function getMerkleTreeByIndex(bytes32 spaceId, uint256 merkle_tree_index)
        public
        view
        returns (MerkleTree memory)
    {
        return SpaceMerkleTree[spaceId][merkle_tree_index];
    }

    function getMerkleTreeCountBySpace(bytes32 spaceId)
        public
        view
        returns (uint256)
    {
        return LastRecordedMerkleTreeIndex[spaceId].add(1);
    }

    function GetMerklePath(bytes32 spaceId, uint256 leafNodeIndex)
        public
        view
        returns (
            uint256,
            uint256,
            bytes32[] memory,
            bool[] memory
        )
    {
        uint256 treeIndex = LastRecordedMerkleTreeIndex[spaceId];
        MerkleTree storage tree = SpaceMerkleTree[spaceId][treeIndex];
        uint256 lastRecordLeafIndex = tree.lastLeafIndex;
        require(lastRecordLeafIndex >= leafNodeIndex, 'not recorded yet');

        for (; treeIndex >= 0; treeIndex--) {
            if (
                leafNodeIndex >=
                SpaceMerkleTree[spaceId][treeIndex].firstLeafIndex
            ) break;
        }
        MerkleTree storage locatedTree = SpaceMerkleTree[spaceId][treeIndex];
        uint256 index = leafNodeIndex - locatedTree.firstLeafIndex;
        uint256 pathLength;
        bytes32[pathMaximalLength] memory path;
        bool[pathMaximalLength] memory isLeftNeighbors;
        (pathLength, path, isLeftNeighbors) = _generatePath(
            locatedTree,
            index,
            TreeMaximalSize
        );

        bytes32[] memory neighbors = new bytes32[](pathLength);
        bool[] memory positions = new bool[](pathLength);

        for (uint256 i = 0; i < pathLength; i++) {
            neighbors[i] = path[i];
            positions[i] = isLeftNeighbors[i];
        }
        return (treeIndex, pathLength, neighbors, positions);
    }

    function merkleProof(
        bytes32 spaceId,
        uint256 _treeIndex,
        bytes32 _leafHash,
        bytes32[] calldata _merkelTreePath,
        bool[] calldata _isLeftNode
    ) external view returns (bool) {
        if (
            SpaceMerkleTree[spaceId][_treeIndex].firstLeafIndex == 0 ||
            _merkelTreePath.length != _isLeftNode.length
        ) {
            return false;
        }
        MerkleTree memory merkleTree = SpaceMerkleTree[spaceId][_treeIndex];

        for (uint256 i = 0; i < _merkelTreePath.length; i++) {
            if (_isLeftNode[i]) {
                _leafHash = sha256(abi.encode(_merkelTreePath[i], _leafHash));
                continue;
            }
            _leafHash = sha256(abi.encode(_leafHash, _merkelTreePath[i]));
        }
        return _leafHash == merkleTree.merkleTreeRoot;
    }

    function _leavesToTree(bytes32[] memory _leaves, uint256 maximalTreeSize)
        private
        pure
        returns (bytes32[] memory, uint256)
    {
        uint256 leafCount = _leaves.length;
        bytes32 left;
        bytes32 right;

        uint256 newAdded = 0;
        uint256 i = 0;

        bytes32[] memory nodes = new bytes32[](maximalTreeSize);

        for (uint256 t = 0; t < leafCount; t++) {
            nodes[t] = _leaves[t];
        }

        uint256 nodeCount = leafCount;
        if (_leaves.length.mod(2) == 1) {
            nodes[leafCount] = (_leaves[leafCount.sub(1)]);
            nodeCount = nodeCount.add(1);
        }

        // uint256 nodeToAdd = nodes.length / 2;
        uint256 nodeToAdd = nodeCount.div(2);

        while (i < nodeCount.sub(1)) {
            left = nodes[i];
            i = i.add(1);

            right = nodes[i];
            i = i.add(1);

            nodes[nodeCount] = sha256(abi.encode(left, right));
            nodeCount = nodeCount.add(1);

            if (++newAdded != nodeToAdd) continue;

            if (nodeToAdd.mod(2) == 1 && nodeToAdd != 1) {
                nodeToAdd = nodeToAdd.add(1);
                nodes[nodeCount] = nodes[nodeCount.sub(1)];
                nodeCount = nodeCount.add(1);
            }

            nodeToAdd = nodeToAdd.div(2);
            newAdded = 0;
        }

        return (nodes, nodeCount);
    }

    function _generateMerkleTree(bytes32 spaceId, uint256 merkle_tree_index)
        private
        view
        returns (MerkleTree memory, bytes32[] memory)
    {
        bytes32[] memory allNodes;
        uint256 nodeCount;
        bytes32[] memory leafNodes = treeLeafList[spaceId][merkle_tree_index]
            .values();

        uint256 treeMaximalSize = spaceInfoMap[spaceId].maxLeafCount * 2;

        bool isFullTree = spaceInfoMap[spaceId].maxLeafCount ==
            leafNodes.length;
        uint256 firstLeafIndex = spaceInfoMap[spaceId].maxLeafCount *
            merkle_tree_index;
        uint256 lastLeafIndex = firstLeafIndex.add(leafNodes.length).sub(1);
        (allNodes, nodeCount) = _leavesToTree(leafNodes, treeMaximalSize);
        MerkleTree memory merkleTree = MerkleTree(
            spaceId,
            merkle_tree_index,
            firstLeafIndex,
            lastLeafIndex,
            allNodes[nodeCount - 1],
            isFullTree
        );

        bytes32[] memory treeNodes = new bytes32[](nodeCount);
        for (uint256 t = 0; t < nodeCount; t++) {
            treeNodes[t] = allNodes[t];
        }
        return (merkleTree, treeNodes);
    }

    function _generatePath(
        MerkleTree memory _merkleTree,
        uint256 _index,
        uint256 treeMaximalSize
    )
        private
        view
        returns (
            uint256,
            bytes32[pathMaximalLength] memory,
            bool[pathMaximalLength] memory
        )
    {
        bytes32[] memory leaves = treeLeafList[_merkleTree.spaceId][
            _merkleTree.merkleTreeIndex
        ].values();
        bytes32[] memory allNodes;
        uint256 nodeCount;

        (allNodes, nodeCount) = _leavesToTree(leaves, treeMaximalSize);

        bytes32[] memory nodes = new bytes32[](nodeCount);
        for (uint256 t = 0; t < nodeCount; t++) {
            nodes[t] = allNodes[t];
        }

        return _generatePath(nodes, leaves.length, _index);
    }

    function _generatePath(
        bytes32[] memory _nodes,
        uint256 _leafCount,
        uint256 _index
    )
        private
        pure
        returns (
            uint256,
            bytes32[pathMaximalLength] memory,
            bool[pathMaximalLength] memory
        )
    {
        bytes32[pathMaximalLength] memory neighbors;
        bool[pathMaximalLength] memory isLeftNeighbors;
        uint256 indexOfFirstNodeInRow = 0;
        uint256 nodeCountInRow = _leafCount;
        bytes32 neighbor;
        bool isLeftNeighbor;
        uint256 shift;
        uint256 i = 0;

        while (_index < _nodes.length.sub(1)) {
            if (_index.mod(2) == 0) {
                // add right neighbor node
                neighbor = _nodes[_index.add(1)];
                isLeftNeighbor = false;
            } else {
                // add left neighbor node
                neighbor = _nodes[_index.sub(1)];
                isLeftNeighbor = true;
            }

            neighbors[i] = neighbor;
            isLeftNeighbors[i] = isLeftNeighbor;
            i = i.add(1);

            nodeCountInRow = nodeCountInRow.mod(2) == 0
                ? nodeCountInRow
                : nodeCountInRow.add(1);
            shift = _index.sub(indexOfFirstNodeInRow).div(2);
            indexOfFirstNodeInRow = indexOfFirstNodeInRow.add(nodeCountInRow);
            _index = indexOfFirstNodeInRow.add(shift);
            nodeCountInRow = nodeCountInRow.div(2);
        }

        return (i, neighbors, isLeftNeighbors);
    }
}
