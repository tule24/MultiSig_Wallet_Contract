// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "hardhat/console.sol";
import "./MultiSigWallet.sol";

contract MultiSigFactory {
    // --------------- STORAGE ----------------
    uint256 id;
    mapping(uint256 => address) public multiSigWalletInstances;
    mapping(address => mapping(address => bool)) public ownerWallets;

    // --------------- EVENT ----------------
    event WalletCreated(
        address createdBy,
        uint256 idWallet,
        address addressWallet,
        address[] owners,
        uint256 required
    );

    function createWallet(address[] calldata _owners, uint256 _required)
        external
    {
        MultiSigWallet newMultiSigWalletContract = new MultiSigWallet(
            _owners,
            _required,
            address(this)
        );

        id += 1;
        multiSigWalletInstances[id] = address(newMultiSigWalletContract);

        for (uint256 i; i < _owners.length; i++) {
            ownerWallets[_owners[i]][address(newMultiSigWalletContract)] = true;
        }
        emit WalletCreated(
            msg.sender,
            id,
            address(newMultiSigWalletContract),
            _owners,
            _required
        );
    }

    function updateOwner(
        address _owner,
        address _multiSigContractAddress,
        bool _isAdd
    ) external {
        if (_isAdd) {
            ownerWallets[_owner][address(_multiSigContractAddress)] = true;
        } else {
            ownerWallets[_owner][address(_multiSigContractAddress)] = false;
        }
    }
}
