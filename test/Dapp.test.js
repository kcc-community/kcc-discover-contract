const {
          deployProxy,
          upgradeProxy,
      }         = require("@openzeppelin/truffle-upgrades");
const {
          BN,
          ether,
          balance,
          expectEvent,
          expectRevert,
      }         = require("@openzeppelin/test-helpers");
const {fromWei} = require("web3-utils");
const {expect}  = require("chai");

const priCategory = ["DeFi", "Infrastructure", "Tools"];
const secCategory = ["Exchange", "NFT", "Game", "Earn", "Lending", "DAO", "Wallet", "Community", "Others"];
const VERIFY_ROLE = web3.utils.soliditySha3("VERIFIER_ROLE");

const DappStore = artifacts.require("DappStore");
// const DappStoreV2 = artifacts.require("DappStoreV2");

let Store;
before(async function () {
    Store = await deployProxy(DappStore, [priCategory, secCategory]);
});

contract("Dapp", function ([deployer, unauthenticated, verifier, owner1, owner2, owner3, commentator, liker]) {
    const amount = ether("1").toString();
    let options  = ["", "", "", "", "", "", "", "", ""];
    let info     = ["title", 0, 0, "shortIntroduction", "logoLink", "bannerLink", "websiteLink", "0x00000000", "xx@gmail.com", amount];

    it("verifier role check", async function () {
        await expectRevert(Store.addPrimaryCategory("XX", {from: unauthenticated}), "DS: caller is not the verifier");
    });

    it("grant role", async function () {
        const receipt = await Store.grantRole(VERIFY_ROLE, verifier);
        await expectEvent(receipt, "RoleGranted", {
            role:    VERIFY_ROLE,
            account: verifier,
            sender:  deployer,
        });
    });

    it("new pri category", async function () {
        const category = "NewPriCategory";
        const receipt  = await Store.addPrimaryCategory(category, {from: verifier});
        await expectEvent(receipt, "AddPrimaryCategory", {
            index:           new BN(priCategory.length),
            primaryCategory: category,
        });
    });

    it("new sec category", async function () {
        const category = "NewSecCategory";
        const receipt  = await Store.addSecondaryCategory(category, {from: verifier});

        await expectEvent(receipt, "AddSecondaryCategory", {
            index:             new BN(secCategory.length),
            secondaryCategory: category,
        });
    });

    it("require: primary category index", async function () {
        info[1] = 999;
        await expectRevert(Store.submitProjectInfo(info, options, {from: owner1}), "DS: primaryCategory error");
        info[1] = 0;
    });


    it("require: second category index", async function () {
        info[2] = 999;
        await expectRevert(Store.submitProjectInfo(info, options, {from: owner1}), "DS: secondaryCategory error");
        info[2] = 0;
    });

    describe("submit a project", async function () {
        let balanceBefore;
        let submitReceipt;
        let erc20BalanceBefore;
        before(async function () {
            balanceBefore      = await balance.current(owner1);
            erc20BalanceBefore = await balance.current(Store.address);
            submitReceipt      = await Store.submitProjectInfo(info, options, {
                value: amount,
                from:  owner1,
            });
        });

        it("before - after = margined + gasUsed * gasPrice", async function () {
            const erc20BalanceAfter = await balance.current(Store.address);
            const balanceAfter      = await balance.current(owner1);
            const gasPrice          = await web3.eth.getGasPrice();
            expect(balanceBefore.sub(balanceAfter)).to.be.bignumber.equal(erc20BalanceAfter.sub(erc20BalanceBefore).add(new BN(submitReceipt.receipt.gasUsed * gasPrice)));
        });

        it("expect event", async function () {
            expectEvent(submitReceipt, "SubmitProjectInfo", {projectAddress: owner1});
        });

        it("unique project address", async function () {
            const promise = Store.submitProjectInfo(info, options, {
                value: amount,
                from:  owner1,
            });
            await expectRevert(promise, "DS: only one submission is allowed for an account");
        });
    });

    describe("audit project info", async function () {
        const update = [["", "", "", "", "", "", "", "", ""], "1", "1", "shortIntroduction", "logoLink", "bannerLink", "websiteLink", new BN(0).toString()];
        describe("succeeded", async function () {
            before(async function () {
                await Store.submitProjectInfo(info, options, {
                    value: amount,
                    from:  owner2,
                });
            });

            it("event", async function () {
                const receipt = await Store.successSubmittedProjectInfo(owner2, {from: verifier});
                expectEvent(receipt, "VerifySubmitProjectInfo", {
                    projectAddress: owner2,
                    status:         new BN(2).toString(),
                });
            });

            it("access control", async function () {
                await expectRevert(Store.updateProjectInfo(owner2, update, {from: owner3}), "DS: projectAddress must be equal to msg.sender");
            });

            it("update info", async function () {
                const receipt = await Store.updateProjectInfo(owner2, update, {from: owner2});
                expectEvent(receipt, "UpdateProjectInfo", {
                    projectAddress: owner2,
                    _changedInfo:   update,
                });
            });

            it("verify updated info", async function () {
                let receipt = await Store.successUpdatedProjectInfo(owner2, {from: verifier});
                // console.info(receipt.logs[0].args);
                expectEvent(receipt, "VerifyUpdateProjectInfo", {
                    projectAddress: owner2,
                    version:        "1",
                    isUpdate:       true,
                });
            });

            it("new minMarginAmount", async function () {
                const newAmount = new BN(10).mul(new BN(amount));
                const receipt   = await Store.updateMinMarginAmount(newAmount.toString());
                expectEvent(receipt, "UpdateMinMarginAmount", {amount: newAmount});
            });

            it("update info: insufficient", async function () {
                update[update.length - 1] = amount;
                const promise = Store.updateProjectInfo(owner2, update, {
                    value: amount,
                    from:  owner2,
                });

                await expectRevert(promise, "DS: insufficient margin amount");
                await Store.updateMinMarginAmount(amount.toString());
            });

            it("update info: add margin", async function () {
                const erc20BalanceBefore  = await balance.current(Store.address);
                update[update.length - 1] = amount;

                const receipt = await Store.updateProjectInfo(owner2, update, {
                    value: amount,
                    from:  owner2,
                });

                const erc20BalanceAfter = await balance.current(Store.address);
                expect(erc20BalanceAfter.sub(erc20BalanceBefore)).to.be.bignumber.equal(amount);
                expectEvent(receipt, "UpdateProjectInfo", {
                    projectAddress: owner2,
                    _changedInfo:   update,
                });
            });

            it("update info: refund amount", async function () {
                const erc20BalanceBefore  = await balance.current(Store.address);
                const owner2BalanceBefore = await balance.current(owner2);

                const receipt = await Store.defeatUpdatedProjectInfo(owner2, {from: verifier});
                // console.info(receipt.logs[0].args);
                expectEvent(receipt, "VerifyUpdateProjectInfo", {
                    projectAddress: owner2,
                    version:        "2",
                    isUpdate:       false,
                });

                const erc20BalanceAfter  = await balance.current(Store.address);
                const owner2BalanceAfter = await balance.current(owner2);
                expect(erc20BalanceBefore.sub(erc20BalanceAfter)).to.be.bignumber.equal(owner2BalanceAfter.sub(owner2BalanceBefore));
            });
        });

        describe("defeated", async function () {
            let balanceBefore;
            before(async function () {
                await Store.submitProjectInfo(info, options, {
                    value: amount,
                    from:  owner3,
                });
            });
            it("event", async function () {
                balanceBefore = await balance.current(owner3);
                const receipt = await Store.defeatSubmittedProjectInfo(owner3, {from: verifier});
                expectEvent(receipt, "VerifySubmitProjectInfo", {
                    projectAddress: owner3,
                    status:         new BN(3).toString(),
                });
            });

            it("refund margin", async function () {
                const balanceAfter = await balance.current(owner3);
                expect(balanceAfter).to.be.bignumber.equal(balanceBefore.add(new BN(amount)));
            });
        });
    });

    // describe("proxy upgrades", async function () {
    //     let StoreV2;
    //     before(async function () {
    //         StoreV2 = await upgradeProxy(Store.address, DappStoreV2);
    //     });
    //
    //     it("project address exists", async function () {
    //         const promise = StoreV2.submitProjectInfo(info, options, {
    //             value: amount,
    //             from:  owner1,
    //         });
    //         await expectRevert(promise, "DS: one project can be submitted at the same address");
    //     });
    //
    //     it("defeat project info: refund amount", async function () {
    //         const owner1BalanceBefore = await balance.current(owner1);
    //         const erc20BalanceBefore  = await balance.current(StoreV2.address);
    //         let receipt               = await StoreV2.defeatSubmittedProjectInfo(owner1, {from: verifier});
    //
    //         const owner1BalanceAfter = await balance.current(owner1);
    //         const erc20BalanceAfter  = await balance.current(StoreV2.address);
    //         expect(owner1BalanceAfter.sub(owner1BalanceBefore)).to.be.bignumber.equal(amount);
    //         expect(erc20BalanceBefore.sub(erc20BalanceAfter)).to.be.bignumber.equal(owner1BalanceAfter.sub(owner1BalanceBefore));
    //         expectEvent(receipt, "VerifySubmitProjectInfo", {
    //             projectAddress: owner1,
    //             status:         "3",
    //         });
    //     });
    // });
});