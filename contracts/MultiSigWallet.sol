// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "hardhat/console.sol";
import "./MutiSigFactory.sol";

contract MultiSigWallet {
    // --------------- STORAGE ----------------
    address multiSigFactory; // address of factory
    uint256 public id; // current id, it can transactionID (for transfer) or consensusID (for change consensus rule)
    mapping(address => bool) public isOwner; // check address is owner

    // ID
    enum State {
        Pending,
        Success,
        Fail
    }
    enum IdType {
        Transaction,
        Consensus
    }
    struct IdInfo {
        // info about an id
        State state; // state of transaction
        IdType idType;
        uint256 totalApproval; // total approve
        uint256 totalReject; // total reject
    }
    mapping(uint256 => IdInfo) public idsInfo; // id => idInfo
    mapping(uint256 => mapping(address => bool)) public voted; // id => owner => isVoted

    // TRANSACTION
    struct Transaction {
        // info about trans
        address to; // receiver
        uint256 amount; // amount
    }
    mapping(uint256 => Transaction) public transactions; // id => trans
    uint256 public transPending; // check whether any transactionID are currently unresolve
    /* 
        If there is any transactionID still unresolved, wallet won't let user creat a new consensusID
        Because it can change consensus rule of pending transaction
    */

    // CONSENSUS
    struct Consensus {
        // info about consensus rule
        uint256 totalOwner; // total owner of waller
        uint256 approvalsRequired; // minimum approvals require
    }
    Consensus public consensus;
    struct ConsChangeInfo {
        address[] addOwners;
        address[] delOwners;
        uint256 approvalsRequired;
    }
    ConsChangeInfo public consChangeInfo;
    bool isConsChanging; // check whether any consensusID are currently unresolve

    /* 
        If there is any consensusID still unresolved, wallet won't let user create a new transaction. 
        Only 1 consensusID is allowed at a time, and make sure to resolve it before creating a new transactionID or consensusID
        Because we have to make sure about consensus rule before creating a new ID  
    */

    // --------------- CONSTRUCTOR ----------------
    constructor(
        address[] memory _owners,
        uint256 _required,
        address _multiSigFactory
    ) {
        uint256 totalOwner = _owners.length;
        require(totalOwner > 0, "owners required");
        require(
            _required > 0 && _required <= totalOwner,
            "invalid required number of owners"
        );

        for (uint256 i; i < totalOwner; i++) {
            address owner = _owners[i];

            require(owner != address(0), "invalid owner");
            isOwner[owner] = true;
        }

        consensus.totalOwner = totalOwner;
        consensus.approvalsRequired = _required;
        multiSigFactory = _multiSigFactory;
    }

    // --------------- MODIFIER ----------------
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }
    modifier isIdExist(uint256 _id) {
        require(_id <= id, "not exist id");
        _;
    }
    modifier notVoted(uint256 _id) {
        require(!voted[_id][msg.sender], "user already voted this trans");
        _;
    }
    modifier notExecuted(uint256 _id) {
        require(idsInfo[_id].state == State.Pending, "ID already resolve");
        _;
    }

    // --------------- EVENT ----------------
    event Deposit(address indexed sender, uint256 amount);
    event CreateTrans(
        uint256 indexed id,
        address indexed creator,
        address to,
        uint256 amount
    );
    event CreateCons(uint256 indexed id, address indexed creator);
    event Voted(uint256 indexed id, address indexed owner, bool isApproved);
    event Success(uint256 indexed id);
    event Fail(uint256 indexed id);

    // --------------- FUNCTION ----------------

    // fallback when deposit to wallet
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /* ----- TRANSACTION ----- */
    // create a new transaction
    function createTrans(address _to, uint256 _amount) external onlyOwner {
        require(!isConsChanging, "Consensus is changing"); // make sure there isn't pending consensusID

        transactions[id] = Transaction({to: _to, amount: _amount});
        handleCreate(IdType.Transaction);

        emit CreateTrans(id, msg.sender, _to, _amount);
    }

    // execute transaction: compare totalApprove and totalReject with approvalsRequired to should execute or cancel this trans
    function resolveTrans(uint256 _id, IdInfo storage idInfo) private {
        Transaction memory transaction = transactions[_id];

        if (
            idInfo.totalReject >
            consensus.totalOwner - consensus.approvalsRequired
        ) {
            idInfo.state = State.Fail;
            transPending -= 1;
            emit Fail(_id);
        } else if (idInfo.totalApproval >= consensus.approvalsRequired) {
            require(
                address(this).balance > transaction.amount,
                "insufficient balance"
            );
            (bool success, ) = transaction.to.call{value: transaction.amount}(
                ""
            );
            require(success, "transfer failed");
            idInfo.state = State.Success;
            transPending -= 1;
            emit Success(_id);
        }
    }

    /* ----- CONSENSUS ----- */
    // create consensus
    function createCons(
        address[] calldata _addOwners,
        address[] calldata _delOwners,
        uint256 _approvalsRequired
    ) external onlyOwner {
        require(transPending == 0, "transaction pending"); // make sure there isn't pending transactionID

        if (_approvalsRequired > 0) {
            consChangeInfo.approvalsRequired = _approvalsRequired;
        }
        if (_addOwners.length > 0) {
            consChangeInfo.addOwners = _addOwners;
        }
        if (_delOwners.length > 0) {
            consChangeInfo.delOwners = _delOwners;
        }

        handleCreate(IdType.Transaction);
        emit CreateCons(id, msg.sender);
    }

    function resolveCons(uint256 _id, IdInfo storage idInfo) private {
        if (
            idInfo.totalReject >
            consensus.totalOwner - consensus.approvalsRequired
        ) {
            idInfo.state = State.Fail;
            isConsChanging = false;
            emit Fail(_id);
        } else if (idInfo.totalApproval >= consensus.approvalsRequired) {
            address[] memory addOwners = consChangeInfo.addOwners;
            uint256 addLen = addOwners.length;
            address[] memory delOwners = consChangeInfo.delOwners;
            uint256 delLen = delOwners.length;
            uint256 approvalsRequired = consChangeInfo.approvalsRequired;
            MultiSigFactory factory = MultiSigFactory(multiSigFactory);

            require(
                consensus.totalOwner + addLen > delLen,
                "Not delete all user"
            );
            consensus.totalOwner = consensus.totalOwner + addLen - delLen;
            if (addLen > 0) {
                for (uint256 i = 0; i < addLen; i++) {
                    address owner = addOwners[i];
                    require(owner != address(0), "invalid owner");
                    require(!isOwner[owner], "owner existed");
                    isOwner[owner] = true;
                    factory.updateOwner(owner, address(this), true);
                }
            }
            if (delLen > 0) {
                for (uint256 i = 0; i < delLen; i++) {
                    address owner = delOwners[i];
                    require(isOwner[owner], "owner not exist");
                    isOwner[owner] = false;
                    factory.updateOwner(owner, address(this), false);
                }
            }

            if (approvalsRequired > 0) {
                require(
                    approvalsRequired <= consensus.totalOwner,
                    "invalid required number of owners"
                );
                consensus.approvalsRequired = approvalsRequired;
            }

            delete consChangeInfo;
            idInfo.state = State.Success;
            isConsChanging = false;
            emit Success(_id);
        }
    }

    // owner vote for id: approve or not approve
    function vote(
        uint256 _id,
        bool _vote,
        IdType _idType
    ) external onlyOwner isIdExist(_id) notVoted(_id) notExecuted(_id) {
        voted[_id][msg.sender] = true;
        emit Voted(_id, msg.sender, _vote);

        IdInfo storage idInfo = idsInfo[_id];
        if (_vote) {
            idInfo.totalApproval += 1;
        } else {
            idInfo.totalReject += 1;
        }

        if (_idType == IdType.Transaction) {
            resolveTrans(_id, idInfo);
        } else {
            resolveCons(_id, idInfo);
        }
    }

    // helper: handle create
    function handleCreate(IdType _idType) private {
        id += 1;
        voted[id][msg.sender] = true;
        idsInfo[id] = IdInfo({
            state: State.Pending,
            idType: _idType,
            totalApproval: 1,
            totalReject: 0
        });

        if (_idType == IdType.Transaction) {
            transPending += 1;
        } else {
            isConsChanging = true;
        }
    }
}
