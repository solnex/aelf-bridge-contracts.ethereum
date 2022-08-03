import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
pragma solidity 0.8.9;

contract Regiment {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    address private controller;
    uint256 private memberJoinLimit;
    uint256 private regimentLimit;
    uint256 private maximumAdminsCount;

    uint256 public DefaultMemberJoinLimit = 256;
    uint256 public DefaultRegimentLimit = 1024;
    uint256 public DefaultMaximumAdminsCount = 3;
    uint256 public regimentCount;
    mapping(bytes32 => RegimentInfo) private regimentInfoMap;
    mapping(bytes32 => EnumerableSet.AddressSet) private regimentMemberListMap;

    event RegimentCreated(
        uint256 createTime,
        address manager,
        address[] initialMemberList,
        bytes32 regimentId
    );

    event NewMemberApplied(bytes32 regimentId, address applyMemberAddress);
    event NewMemberAdded(
        bytes32 regimentId,
        address newMemberAddress,
        address operatorAddress
    );

    event RegimentMemberLeft(
        bytes32 regimentId,
        address leftMemberAddress,
        address operatorAddress
    );

    struct RegimentInfo {
        uint256 createTime;
        address manager;
        EnumerableSet.AddressSet admins;
        bool isApproveToJoin;
    }
    struct RegimentInfoForView {
        uint256 createTime;
        address manager;
        address[] admins;
        bool isApproveToJoin;
    }
    modifier assertSenderIsController() {
        require(msg.sender == controller, 'Sender is not the Controller.');
        _;
    }

    constructor(
        uint256 _memberJoinLimit,
        uint256 _regimentLimit,
        uint256 _maximumAdminsCount
    ) {
        require(
            _memberJoinLimit <= DefaultMemberJoinLimit,
            'Invalid memberJoinLimit'
        );
        require(
            _regimentLimit <= DefaultRegimentLimit,
            'Invalid regimentLimit'
        );
        require(
            _maximumAdminsCount <= DefaultMaximumAdminsCount,
            'Invalid maximumAdminsCount'
        );
        controller = msg.sender;
        memberJoinLimit = _memberJoinLimit;
        regimentLimit = _regimentLimit;
        maximumAdminsCount = _maximumAdminsCount == 0
            ? DefaultMaximumAdminsCount
            : _maximumAdminsCount;
        require(memberJoinLimit <= regimentLimit, 'Incorrect MemberJoinLimit.');
    }

    function CreateRegiment(
        address manager,
        address[] calldata initialMemberList,
        bool isApproveToJoin
    ) external assertSenderIsController returns (bytes32) {
        bytes32 regimentId = sha256(abi.encodePacked(regimentCount, manager));
        regimentCount = regimentCount.add(1);
        EnumerableSet.AddressSet storage memberList = regimentMemberListMap[
            regimentId
        ];
        for (uint256 i; i < initialMemberList.length; i++) {
            memberList.add(initialMemberList[i]);
        }
        if (!memberList.contains(manager)) {
            memberList.add(manager);
        }
        require(
            memberList.length() <= memberJoinLimit,
            'Too many initial members.'
        );
        regimentInfoMap[regimentId].createTime = block.timestamp;
        regimentInfoMap[regimentId].manager = manager;
        regimentInfoMap[regimentId].isApproveToJoin = isApproveToJoin;
        emit RegimentCreated(
            block.timestamp,
            manager,
            initialMemberList,
            regimentId
        );
        return regimentId;
    }

    function JoinRegiment(
        bytes32 regimentId,
        address newMerberAddess,
        address originSenderAddress
    ) external assertSenderIsController {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        EnumerableSet.AddressSet storage memberList = regimentMemberListMap[
            regimentId
        ];
        require(
            memberList.length() <= regimentLimit,
            'Regiment member reached the limit'
        );
        if (
            regimentInfo.isApproveToJoin ||
            memberList.length() >= memberJoinLimit
        ) {
            emit NewMemberApplied(regimentId, newMerberAddess);
        } else {
            memberList.add(newMerberAddess);
            emit NewMemberAdded(
                regimentId,
                newMerberAddess,
                originSenderAddress
            );
        }
    }

    function LeaveRegiment(
        bytes32 regimentId,
        address leaveMemberAddress,
        address originSenderAddress
    ) external assertSenderIsController {
        EnumerableSet.AddressSet storage memberList = regimentMemberListMap[
            regimentId
        ];
        require(originSenderAddress == leaveMemberAddress, 'No permission.');
        memberList.remove(leaveMemberAddress);
        emit RegimentMemberLeft(
            regimentId,
            leaveMemberAddress,
            originSenderAddress
        );
    }

    function AddRegimentMember(
        bytes32 regimentId,
        address newMerberAddess,
        address originSenderAddress
    ) external assertSenderIsController {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        EnumerableSet.AddressSet storage memberList = regimentMemberListMap[
            regimentId
        ];
        require(
            memberList.length() <= regimentLimit,
            'Regiment member reached the limit'
        );
        require(
            regimentInfo.admins.contains(originSenderAddress) ||
                regimentInfo.manager == originSenderAddress,
            'Origin sender is not manager or admin of this regiment'
        );
        memberList.add(newMerberAddess);
        emit NewMemberAdded(regimentId, newMerberAddess, originSenderAddress);
    }

    function DeleteRegimentMember(
        bytes32 regimentId,
        address leaveMemberAddress,
        address originSenderAddress
    ) external assertSenderIsController {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        EnumerableSet.AddressSet storage memberList = regimentMemberListMap[
            regimentId
        ];
        require(
            memberList.length() <= regimentLimit,
            'Regiment member reached the limit'
        );
        require(
            regimentInfo.admins.contains(originSenderAddress) ||
                regimentInfo.manager == originSenderAddress,
            'Origin sender is not manager or admin of this regiment'
        );
        memberList.remove(leaveMemberAddress);
        emit RegimentMemberLeft(
            regimentId,
            leaveMemberAddress,
            originSenderAddress
        );
    }

    function ChangeController(address _controller)
        external
        assertSenderIsController
    {
        controller = _controller;
    }

    function ResetConfig(
        uint256 _memberJoinLimit,
        uint256 _regimentLimit,
        uint256 _maximumAdminsCount
    ) external assertSenderIsController {
        memberJoinLimit = _memberJoinLimit == 0
            ? memberJoinLimit
            : _memberJoinLimit;
        regimentLimit = _regimentLimit == 0 ? regimentLimit : _regimentLimit;
        maximumAdminsCount = _maximumAdminsCount == 0
            ? maximumAdminsCount
            : _maximumAdminsCount;
        require(memberJoinLimit <= regimentLimit, 'Incorrect MemberJoinLimit.');
    }

    function TransferRegimentOwnership(
        bytes32 regimentId,
        address newManagerAddress,
        address originSenderAddress
    ) external assertSenderIsController {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        require(originSenderAddress == regimentInfo.manager, 'No permission.');
        regimentInfo.manager = newManagerAddress;
    }

    function AddAdmins(
        bytes32 regimentId,
        address[] calldata newAdmins,
        address originSenderAddress
    ) external assertSenderIsController {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        require(originSenderAddress == regimentInfo.manager, 'No permission.');
        for (uint256 i; i < newAdmins.length; i++) {
            require(
                !regimentInfo.admins.contains(newAdmins[i]),
                'someone is already an admin'
            );
            regimentInfo.admins.add(newAdmins[i]);
        }
        require(
            regimentInfo.admins.length() <= maximumAdminsCount,
            'Admins count cannot greater than maximumAdminsCount'
        );
    }

    function DeleteAdmins(
        bytes32 regimentId,
        address[] calldata deleteAdmins,
        address originSenderAddress
    ) external assertSenderIsController {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        require(originSenderAddress == regimentInfo.manager, 'No permission.');
        for (uint256 i; i < deleteAdmins.length; i++) {
            require(
                regimentInfo.admins.contains(deleteAdmins[i]),
                'someone is not an admin'
            );
            regimentInfo.admins.add(deleteAdmins[i]);
        }
    }

    //view functions

    function GetController() external view returns (address) {
        return controller;
    }

    function GetConfig()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (maximumAdminsCount, memberJoinLimit, regimentLimit);
    }

    function GetRegimentInfo(bytes32 regimentId)
        external
        view
        returns (RegimentInfoForView memory)
    {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        return
            RegimentInfoForView({
                createTime: regimentInfo.createTime,
                manager: regimentInfo.manager,
                admins: regimentInfo.admins.values(),
                isApproveToJoin: regimentInfo.isApproveToJoin
            });
    }

    function IsRegimentMember(bytes32 regimentId, address memberAddress)
        external
        view
        returns (bool)
    {
        EnumerableSet.AddressSet storage memberList = regimentMemberListMap[
            regimentId
        ];
        return memberList.contains(memberAddress);
    }

    function IsRegimentAdmin(bytes32 regimentId, address adminAddress)
        external
        view
        returns (bool)
    {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        return regimentInfo.admins.contains(adminAddress);
    }

    function IsRegimentManager(bytes32 regimentId, address managerAddress)
        external
        view
        returns (bool)
    {
        RegimentInfo storage regimentInfo = regimentInfoMap[regimentId];
        return regimentInfo.manager == managerAddress;
    }

    function GetRegimentMemberList(bytes32 regimentId)
        external
        view
        returns (address[] memory)
    {
        EnumerableSet.AddressSet storage memberList = regimentMemberListMap[
            regimentId
        ];
        return memberList.values();
    }
}
