// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "hardhat/console.sol";
import "./MultiSigWallet.sol";

contract MultiSigFactory {
    // --------------- STORAGE ----------------
    MultiSigWallet[] public multiSigWalletInstances;
    mapping(address => mapping(address => bool)) public ownerWallets;

    // --------------- EVENT ----------------
    event WalletCreated(
        address createdBy,
        address newWalletAddress,
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
        multiSigWalletInstances.push(newMultiSigWalletContract);
        for (uint256 i; i < _owners.length; i++) {
            ownerWallets[_owners[i]][address(newMultiSigWalletContract)] = true;
        }
        emit WalletCreated(
            msg.sender,
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
