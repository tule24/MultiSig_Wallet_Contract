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
        uint256 id;
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
    uint256 public transAmount; // check whether any transactionID are currently unresolve
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
    ConsChangeInfo consChangeInfo;
    bool public isConsChanging; // check whether any consensusID are currently unresolve

    /* 
        If there is any consensusID still unresolved, wallet won't let user create a new transaction. 
        Only 1 consensusID is allowed at a time, and make sure to resolve it before creating a new transactionID or consensusID
        Because we have to make sure about consensus rule before creating a new ID.
        But we can make multiple transaction at a time.  
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

            require(owner != address(0), "invalid address");
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
        require(!voted[_id][msg.sender], "user already voted this id");
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
    event ResolveTrans(
        uint256 indexed id,
        bool success,
        uint256 balance,
        uint256 balanceLock
    );
    event ResolveCons(
        uint256 indexed id,
        bool success,
        address[] addOwners,
        address[] delOwners,
        uint256 approvalsRequired
    );

    // --------------- FUNCTION ----------------

    // fallback when deposit to wallet
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /* ----- TRANSACTION ----- */
    // create a new transaction
    function createTrans(address _to, uint256 _amount) external onlyOwner {
        require(!isConsChanging, "Consensus is changing"); // make sure there isn't pending consensusID
        require(
            address(this).balance > transAmount + _amount,
            "insufficient balance"
        );

        id += 1;
        transactions[id] = Transaction({to: _to, amount: _amount});
        transAmount += _amount;
        createId(IdType.Transaction);

        emit CreateTrans(id, msg.sender, _to, _amount);
    }

    // execute transaction: compare totalApprove and totalReject with approvalsRequired to should execute or cancel this trans
    function resolveTrans(uint256 _id, IdInfo storage idInfo) private {
        Transaction memory transaction = transactions[_id];
        uint256 amount = transaction.amount;
        if (
            idInfo.totalReject >
            consensus.totalOwner - consensus.approvalsRequired
        ) {
            idInfo.state = State.Fail;
            transAmount -= amount;
            emit ResolveTrans(_id, false, address(this).balance, transAmount);
        } else if (idInfo.totalApproval >= consensus.approvalsRequired) {
            require(address(this).balance > amount, "insufficient balance");
            (bool success, ) = transaction.to.call{value: amount}("");
            require(success, "transfer failed");
            idInfo.state = State.Success;
            transAmount -= amount;
            emit ResolveTrans(_id, true, address(this).balance, transAmount);
        }
    }

    /* ----- CONSENSUS ----- */
    // create consensus
    function createCons(
        address[] calldata _addOwners,
        address[] calldata _delOwners,
        uint256 _approvalsRequired
    ) external onlyOwner {
        require(transAmount == 0, "transaction pending"); // make sure there isn't pending transactionID

        uint256 addLen = _addOwners.length;
        uint256 delLen = _delOwners.length;
        require(consensus.totalOwner + addLen > delLen, "Not delete all user");

        if (_approvalsRequired > 0) {
            require(
                _approvalsRequired <= consensus.totalOwner + addLen - delLen,
                "invalid required number of owners"
            );
            consChangeInfo.approvalsRequired = _approvalsRequired;
        }
        if (_addOwners.length > 0) {
            for (uint256 i = 0; i < addLen; i++) {
                address owner = _addOwners[i];
                require(owner != address(0), "invalid address");
                require(!isOwner[owner], "owner existed");
            }
            consChangeInfo.addOwners = _addOwners;
        }
        if (_delOwners.length > 0) {
            for (uint256 i = 0; i < delLen; i++) {
                address owner = _delOwners[i];
                require(isOwner[owner], "owner not exist");
            }
            consChangeInfo.delOwners = _delOwners;
        }

        id += 1;
        isConsChanging = true;
        createId(IdType.Consensus);
        emit CreateCons(id, msg.sender);
    }

    function getConsChangeInfo() external view returns (ConsChangeInfo memory) {
        return consChangeInfo;
    }

    function resolveCons(uint256 _id, IdInfo storage idInfo) private {
        address[] memory addOwners = consChangeInfo.addOwners;
        address[] memory delOwners = consChangeInfo.delOwners;
        uint256 approvalsRequired = consChangeInfo.approvalsRequired;
        if (
            idInfo.totalReject >
            consensus.totalOwner - consensus.approvalsRequired
        ) {
            delete consChangeInfo;
            idInfo.state = State.Fail;
            isConsChanging = false;
            emit ResolveCons(
                _id,
                false,
                addOwners,
                delOwners,
                approvalsRequired
            );
        } else if (idInfo.totalApproval >= consensus.approvalsRequired) {
            uint256 addLen = addOwners.length;
            uint256 delLen = delOwners.length;
            MultiSigFactory factory = MultiSigFactory(multiSigFactory);

            if (addLen > 0) {
                for (uint256 i = 0; i < addLen; i++) {
                    address owner = addOwners[i];
                    isOwner[owner] = true;
                    factory.updateOwner(owner, address(this), true);
                }
            }
            if (delLen > 0) {
                for (uint256 i = 0; i < delLen; i++) {
                    address owner = delOwners[i];
                    isOwner[owner] = false;
                    factory.updateOwner(owner, address(this), false);
                }
            }

            consensus.totalOwner = consensus.totalOwner + addLen - delLen;
            if (approvalsRequired > 0) {
                consensus.approvalsRequired = approvalsRequired;
            }

            idInfo.state = State.Success;
            isConsChanging = false;
            emit ResolveCons(
                _id,
                true,
                addOwners,
                delOwners,
                approvalsRequired
            );
            delete consChangeInfo;
        }
    }

    // owner vote for id: approve or not approve
    function vote(uint256 _id, bool _vote)
        external
        onlyOwner
        isIdExist(_id)
        notVoted(_id)
        notExecuted(_id)
    {
        voted[_id][msg.sender] = true;
        emit Voted(_id, msg.sender, _vote);

        IdInfo storage idInfo = idsInfo[_id];
        if (_vote) {
            idInfo.totalApproval += 1;
        } else {
            idInfo.totalReject += 1;
        }

        if (idInfo.idType == IdType.Transaction) {
            resolveTrans(_id, idInfo);
        } else {
            resolveCons(_id, idInfo);
        }
    }

    // helper: handle create
    function createId(IdType _idType) private {
        voted[id][msg.sender] = true;
        idsInfo[id] = IdInfo({
            id: id,
            state: State.Pending,
            idType: _idType,
            totalApproval: 1,
            totalReject: 0
        });
    }
}
