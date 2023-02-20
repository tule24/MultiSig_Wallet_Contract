const { expect } = require("chai")
const { ethers } = require("hardhat")

describe("MultiSig Factory", () => {
  let multiSigFactory
  let multiSigWallet
  let signers

  before(async () => {
    const MultiSigFactory = await ethers.getContractFactory("MultiSigFactory")
    multiSigFactory = await MultiSigFactory.deploy()
    await multiSigFactory.deployed()
    signers = await ethers.getSigners()
  })

  describe("Create Wallet", () => {
    it("Should revert if owners is empty", async () => {
      const _owners = []
      const _required = 2

      const transaction = multiSigFactory.createWallet(_owners, _required)
      await expect(transaction).to.be.revertedWith("owners required")
    })

    it("Should revert if approval require > total owners", async () => {
      const _owners = [signers[1].address]
      const _required = 2

      const transaction = multiSigFactory.createWallet(_owners, _required)
      await expect(transaction).to.be.revertedWith("invalid required number of owners")
    })

    it("Should revert if approval require < 1", async () => {
      const _owners = [signers[1].address]
      const _required = 0

      const transaction = multiSigFactory.createWallet(_owners, _required)
      await expect(transaction).to.be.revertedWith("invalid required number of owners")
    })

    it("Should revert if there is a address(0)", async () => {
      const _owners = [signers[1].address, ethers.constants.AddressZero]
      const _required = 1

      const transaction = multiSigFactory.createWallet(_owners, _required)
      await expect(transaction).to.be.revertedWith("invalid address")
    })


    it("Should create new wallet success", async () => {
      const _owners = [signers[1].address, signers[2].address, signers[3].address]
      const _required = 2

      const transaction = await multiSigFactory.createWallet(_owners, _required)
      const receipt = await transaction.wait()
      const walletAddress = receipt.events[0].args.addressWallet
      multiSigWallet = await ethers.getContractAt("MultiSigWallet", walletAddress)

      const owner_1 = await multiSigFactory.ownerWallets(signers[1].address, multiSigWallet.address)
      const owner_2 = await multiSigFactory.ownerWallets(signers[2].address, multiSigWallet.address)
      const owner_3 = await multiSigFactory.ownerWallets(signers[3].address, multiSigWallet.address)

      expect(owner_1).to.equal(true)
      expect(owner_2).to.equal(true)
      expect(owner_3).to.equal(true)
    })

    it("Should get exactly info from wallet", async () => {
      const owner_1 = await multiSigWallet.isOwner(signers[1].address)
      const owner_2 = await multiSigWallet.isOwner(signers[2].address)
      const owner_3 = await multiSigWallet.isOwner(signers[3].address)

      expect(owner_1).to.equal(true)
      expect(owner_2).to.equal(true)
      expect(owner_3).to.equal(true)

      const consensus = await multiSigWallet.consensus()
      const { totalOwner, approvalsRequired } = consensus

      expect(totalOwner).to.equal(3)
      expect(approvalsRequired).to.equal(2)
    })
  })

  describe("Deposit wallet", () => {
    it("Should balance increase after deposit", async () => {
      const beforeBalance = await multiSigWallet.provider.getBalance(multiSigWallet.address)
      await signers[5].sendTransaction({ to: multiSigWallet.address, value: ethers.utils.parseEther('10') })
      const afterBalance = await multiSigWallet.provider.getBalance(multiSigWallet.address)

      const diff = afterBalance.sub(beforeBalance)
      expect(ethers.utils.formatEther(diff) * 1).to.equal(10)
    })
  })

  describe("Create a Transaction", () => {
    it("Should revert if caller not owner", async () => {
      const transaction = multiSigWallet.createTrans(signers[4].address, 1)
      await expect(transaction).to.be.revertedWith("Not owner")
    })
    it("Should revert if create transaction that value > wallet balance", async () => {
      const transaction = multiSigWallet.connect(signers[1]).createTrans(signers[4].address, ethers.utils.parseEther('11'))
      await expect(transaction).to.be.revertedWith("insufficient balance")
    })
    it("Should create transaction success", async () => {
      const transaction = await multiSigWallet.connect(signers[1]).createTrans(signers[4].address, ethers.utils.parseEther('1'))
      await transaction.wait()

      const curId = await multiSigWallet.id()
      expect(Number(curId)).to.equal(1)

      const transAmount = await multiSigWallet.transAmount()
      expect(ethers.utils.formatEther(transAmount) * 1).to.equal(1)

      const trans = await multiSigWallet.transactions(curId)
      expect(trans.to).to.equal(signers[4].address)
      expect(ethers.utils.formatEther(trans.amount) * 1).to.equal(1)

      const curIdInfo = await multiSigWallet.idsInfo(curId)
      expect(curIdInfo.id).to.equal(curId)
      expect(curIdInfo.state).to.equal(0)
      expect(curIdInfo.idType).to.equal(0)
      expect(Number(curIdInfo.totalApproval)).to.equal(1)
      expect(Number(curIdInfo.totalReject)).to.equal(0)

      const voted = await multiSigWallet.voted(curId, signers[1].address)
      expect(voted).to.equal(true)
    })
  })

  describe("Voted Transaction", () => {
    it("Should revert if caller not owner", async () => {
      const curId = await multiSigWallet.id()
      const transaction = multiSigWallet.vote(curId, true)
      await expect(transaction).to.be.revertedWith("Not owner")
    })
    it("Should revert if id not exist", async () => {
      const curId = await multiSigWallet.id()
      const newId = curId.add(1)
      const transaction = multiSigWallet.connect(signers[1]).vote(newId, true)
      await expect(transaction).to.be.revertedWith("not exist id")
    })
    it("Should revert if user was voted", async () => {
      const curId = await multiSigWallet.id()
      const transaction = multiSigWallet.connect(signers[1]).vote(curId, true)
      await expect(transaction).to.be.revertedWith("user already voted this id")
    })
    it("Should revert if create a consensusID but there is a transaction pending", async () => {
      const transaction = multiSigWallet.connect(signers[1]).createCons([], [], 2)
      await expect(transaction).to.be.revertedWith("transaction pending")
    })
    it("Should vote success. Vote false => not enought approvals, ID not resolve", async () => {
      const curId = await multiSigWallet.id()
      const transaction = await multiSigWallet.connect(signers[2]).vote(curId, false)
      await transaction.wait()

      const voted = await multiSigWallet.voted(curId, signers[2].address)
      expect(voted).to.equal(true)

      const curIdInfo = await multiSigWallet.idsInfo(curId)
      expect(Number(curIdInfo.totalApproval)).to.equal(1)
      expect(Number(curIdInfo.totalReject)).to.equal(1)
      expect(curIdInfo.state).to.equal(0)
    })
  })

  describe("Resolve ID => Transaction success", () => {
    it("Should transaction execute, ID success", async () => {
      const curId = await multiSigWallet.id()
      const beforeWalletBal = await multiSigWallet.provider.getBalance(multiSigWallet.address)
      const beforeUserBal = await signers[4].getBalance()

      const transaction = await multiSigWallet.connect(signers[3]).vote(curId, true)
      const receipt = await transaction.wait()

      const curIdInfo = await multiSigWallet.idsInfo(curId)
      expect(Number(curIdInfo.totalApproval)).to.equal(2)
      expect(Number(curIdInfo.totalReject)).to.equal(1)
      expect(curIdInfo.state).to.equal(1)

      const transAmount = await multiSigWallet.transAmount()
      expect(ethers.utils.formatEther(transAmount) * 1).to.equal(0)

      const afterWalletBal = await multiSigWallet.provider.getBalance(multiSigWallet.address)
      const afterUserBal = await signers[4].getBalance()

      const diffWallet = beforeWalletBal.sub(afterWalletBal)
      const diffUser = afterUserBal.sub(beforeUserBal)

      expect(diffWallet).to.equal(diffUser)
    })
  })

  describe("Resolve ID => Transaction fail", () => {
    it("Should transaction execute, ID success", async () => {
      const transaction = await multiSigWallet.connect(signers[1]).createTrans(signers[4].address, ethers.utils.parseEther('1'))
      await transaction.wait()

      const beforeWalletBal = await multiSigWallet.provider.getBalance(multiSigWallet.address)
      const beforeUserBal = await signers[4].getBalance()

      const curId = await multiSigWallet.id()
      const vote1 = await multiSigWallet.connect(signers[2]).vote(curId, false)
      await vote1.wait()
      const vote2 = await multiSigWallet.connect(signers[3]).vote(curId, false)
      await vote2.wait()

      const curIdInfo = await multiSigWallet.idsInfo(curId)
      expect(Number(curIdInfo.totalApproval)).to.equal(1)
      expect(Number(curIdInfo.totalReject)).to.equal(2)
      expect(curIdInfo.state).to.equal(2)

      const transAmount = await multiSigWallet.transAmount()
      expect(ethers.utils.formatEther(transAmount) * 1).to.equal(0)

      const afterWalletBal = await multiSigWallet.provider.getBalance(multiSigWallet.address)
      const afterUserBal = await signers[4].getBalance()

      expect(beforeWalletBal).to.equal(afterWalletBal)
      expect(beforeUserBal).to.equal(afterUserBal)
    })
  })

  describe("Create Consensus", () => {
    it("Should revert if caller not owner", async () => {
      const transaction = multiSigWallet.createCons([], [], 2)
      await expect(transaction).to.be.revertedWith("Not owner")
    })
    it("Should revert if total user del > total user add + current total user", async () => {
      const addOwners = [signers[4].address]
      const delOwners = [signers[1].address, signers[2].address, signers[3].address, signers[4].address]
      const transaction = multiSigWallet.connect(signers[1]).createCons(addOwners, delOwners, 2)
      await expect(transaction).to.be.revertedWith("Not delete all user")
    })
    it("Should revert if approval require > total owners", async () => {
      const addOwners = [signers[4].address]
      const delOwners = [signers[1].address]
      const transaction = multiSigWallet.connect(signers[1]).createCons(addOwners, delOwners, 4)
      await expect(transaction).to.be.revertedWith("invalid required number of owners")
    })
    it("Should revert if addOwners have invalid address", async () => {
      const addOwners = [ethers.constants.AddressZero]
      const delOwners = []
      const transaction = multiSigWallet.connect(signers[1]).createCons(addOwners, delOwners, 0)
      await expect(transaction).to.be.revertedWith("invalid address")
    })
    it("Should revert if addOwners have address existed", async () => {
      const addOwners = [signers[1].address]
      const delOwners = []
      const transaction = multiSigWallet.connect(signers[1]).createCons(addOwners, delOwners, 0)
      await expect(transaction).to.be.revertedWith("owner existed")
    })
    it("Should revert if delOwners have address not existed", async () => {
      const addOwners = []
      const delOwners = [signers[5].address]
      const transaction = multiSigWallet.connect(signers[1]).createCons(addOwners, delOwners, 0)
      await expect(transaction).to.be.revertedWith("owner not exist")
    })
    it("Should create consensus success", async () => {
      const addOwners = [signers[5].address]
      const delOwners = [signers[2].address]
      const _required = 3;
      const transaction = await multiSigWallet.connect(signers[1]).createCons(addOwners, delOwners, _required)
      await transaction.wait()

      const curId = await multiSigWallet.id()

      const curIdInfo = await multiSigWallet.idsInfo(curId)
      expect(curIdInfo.id).to.equal(curId)
      expect(curIdInfo.state).to.equal(0)
      expect(curIdInfo.idType).to.equal(1)
      expect(Number(curIdInfo.totalApproval)).to.equal(1)
      expect(Number(curIdInfo.totalReject)).to.equal(0)

      const voted = await multiSigWallet.voted(curId, signers[1].address)
      expect(voted).to.equal(true)

      const isConsChanging = await multiSigWallet.isConsChanging()
      expect(isConsChanging).to.equal(true)

      const consChangeInfo = await multiSigWallet.getConsChangeInfo()
      expect(Number(consChangeInfo.approvalsRequired)).to.equal(3)
      expect(consChangeInfo.addOwners.length).to.equal(1)
      expect(consChangeInfo.delOwners.length).to.equal(1)
    })
    it("Should revert if create a transactionID but there is a consensus pending", async () => {
      const transaction = multiSigWallet.connect(signers[1]).createTrans(signers[4].address, ethers.utils.parseEther('1'))
      await expect(transaction).to.be.revertedWith("Consensus is changing")
    })
  })

  describe("Resolve ID => Consensus success", () => {
    it("Should consensus ID success", async () => {
      const curId = await multiSigWallet.id()
      const transaction = await multiSigWallet.connect(signers[2]).vote(curId, true)
      const receipt = await transaction.wait()

      const curIdInfo = await multiSigWallet.idsInfo(curId)
      expect(Number(curIdInfo.totalApproval)).to.equal(2)
      expect(Number(curIdInfo.totalReject)).to.equal(0)
      expect(curIdInfo.state).to.equal(1)

      const isConsChanging = await multiSigWallet.isConsChanging()
      expect(isConsChanging).to.equal(false)

      const consChangeInfo = await multiSigWallet.getConsChangeInfo()
      expect(Number(consChangeInfo.approvalsRequired)).to.equal(0)
      expect(consChangeInfo.addOwners.length).to.equal(0)
      expect(consChangeInfo.delOwners.length).to.equal(0)

      const consensus = await multiSigWallet.consensus()
      expect(consensus.totalOwner).to.equal(3)
      expect(consensus.approvalsRequired).to.equal(3)

      const owner_1 = await multiSigWallet.isOwner(signers[1].address)
      const owner_2 = await multiSigWallet.isOwner(signers[2].address)
      const owner_3 = await multiSigWallet.isOwner(signers[3].address)
      const owner_5 = await multiSigWallet.isOwner(signers[5].address)

      expect(owner_1).to.equal(true)
      expect(owner_2).to.equal(false)
      expect(owner_3).to.equal(true)
      expect(owner_5).to.equal(true)

      const factory_owner_1 = await multiSigFactory.ownerWallets(signers[1].address, multiSigWallet.address)
      const factory_owner_2 = await multiSigFactory.ownerWallets(signers[2].address, multiSigWallet.address)
      const factory_owner_3 = await multiSigFactory.ownerWallets(signers[3].address, multiSigWallet.address)
      const factory_owner_5 = await multiSigFactory.ownerWallets(signers[5].address, multiSigWallet.address)

      expect(factory_owner_1).to.equal(true)
      expect(factory_owner_2).to.equal(false)
      expect(factory_owner_3).to.equal(true)
      expect(factory_owner_5).to.equal(true)
    })
  })

  describe("Create multiple transaction ID", () => {
    it("Should revert if total amount > wallet balance", async () => {
      const transaction1 = await multiSigWallet.connect(signers[1]).createTrans(signers[4].address, ethers.utils.parseEther('1'))
      await transaction1.wait()

      const transaction2 = multiSigWallet.connect(signers[1]).createTrans(signers[4].address, ethers.utils.parseEther('9'))
      await expect(transaction2).to.be.revertedWith("insufficient balance")
    })
    it("Should create multiple transaction ID success", async () => {
      const transaction1 = await multiSigWallet.connect(signers[1]).createTrans(signers[4].address, ethers.utils.parseEther('1'))
      await transaction1.wait()

      const transAmount = await multiSigWallet.transAmount()
      expect(ethers.utils.formatEther(transAmount) * 1).to.equal(2)
    })
    it("Should multiple transaction work exactly", async () => {
      const beforeWalletBal = await multiSigWallet.provider.getBalance(multiSigWallet.address)
      const beforeUserBal = await signers[4].getBalance()

      const curId = await multiSigWallet.id()
      const transaction3 = await multiSigWallet.connect(signers[3]).vote(curId, true)
      await transaction3.wait()
      const transaction5 = await multiSigWallet.connect(signers[5]).vote(curId, true)
      await transaction5.wait()

      const transAmount1 = await multiSigWallet.transAmount()
      expect(ethers.utils.formatEther(transAmount1) * 1).to.equal(1)

      const preID = curId - 1
      const _transaction3 = await multiSigWallet.connect(signers[3]).vote(preID, true)
      await _transaction3.wait()
      const _transaction5 = await multiSigWallet.connect(signers[5]).vote(preID, true)
      await _transaction5.wait()

      const transAmount2 = await multiSigWallet.transAmount()
      expect(ethers.utils.formatEther(transAmount2) * 1).to.equal(0)

      const afterWalletBal = await multiSigWallet.provider.getBalance(multiSigWallet.address)
      const afterUserBal = await signers[4].getBalance()

      const diffWallet = beforeWalletBal.sub(afterWalletBal)
      const diffUser = afterUserBal.sub(beforeUserBal)

      expect(diffWallet).to.equal(diffUser)
      expect(ethers.utils.formatEther(diffWallet) * 1).to.equal(2)
      expect(ethers.utils.formatEther(afterWalletBal) * 1).to.equal(7)
    })
  })
})