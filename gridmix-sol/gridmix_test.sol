pragma solidity >=0.4.22 <0.7.0;
pragma experimental ABIEncoderV2;

import "remix_tests.sol"; // this import is automatically injected by Remix.
import "remix_accounts.sol";
import "./gridMix.sol";

// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract testSuite is masterSLEC {
    
    /// More special functions are: 'beforeEach', 'beforeAll', 'afterEach' & 'afterAll'
    /// #sender: account-1
    function beforeAll() public {
        // address[] memory operators = new address[](0);
        // token = new KWH(operators, msg.sender);
        token = IERC777(address(0));
        init(msg.sender, address(0));
    }

    /// #sender: account-2
    function registerAccounts2() public {
        register(true, false, 1, 1);
    }
    
    /// #sender: account-3
    function registerAccounts3() public {
        register(false, true, 1, 1);
    }
    
    /// #sender: account-1
    function openMarket() public {
        openMarket(20);
    }
    
    /// #sender: account-2
    function offerEnergy() public {
        offerEnergy(5, 10);
        Assert.equal(sellEnergy_map[msg.sender].length, 1, "account-2 failed to deposit an offerEnergy");
    }
    
    /// #sender: account-3
    function askForEnergy() public {
        askForEnergy(5, 10);
        Assert.equal(buyEnergy_map[msg.sender].length, 1, "account-3 failed to deposit an askForEnergy");
        
        streamRef[] memory offers = findAppropriateSellers(0);
        Assert.equal(offers.length, 1, "no offers found");
        
        address seller = TestsAccounts.getAccount(2);
        Assert.equal(offers[0].addr, seller, "wrong seller address");
        Assert.equal(offers[0].id, 0, "wrong offer id");
    }
    
    /// #sender: account-3
    function bidToOffer() public {
        address seller = TestsAccounts.getAccount(2);
        bidToOffer(0, seller, 0, 10);
        
        Assert.equal(bids[abi.encode(seller, 0)][0].addr, msg.sender, "wrong seller");
        // Assert.equal(bids[abi.encode(seller, 0)][0].id, 0, "wrong offer");
        
        bytes memory ref = getReferenceBidToOffer(0, 0, seller);
        this.tokensReceived(msg.sender, msg.sender, seller, 10, ref, bytes("")); // simulate token transfer
        
        bytes memory internalRef = abi.encode(seller, msg.sender, 0, 0);
        Assert.equal(bids_acquired[internalRef], 10, "wrong bids acquired");
        
        this.tokensReceived(msg.sender, msg.sender, seller, 7, ref, bytes("")); // simulate token transfer
        Assert.equal(bids_acquired[internalRef], 17, "wrong bids acquired");
    }
    
    /// #sender: account-1
    function shouldCloseMarket() public {
        closeMarket();
    }
    
    /// #sender: account-2
    function acceptHighestBid() public {
        acceptHighestBid(0);
        
        address buyer = TestsAccounts.getAccount(3);
        bytes memory offerRef = abi.encode(msg.sender, 0);
        bytes memory buyerRef = abi.encode(buyer, 0);
        Assert.equal(accepted[offerRef].length, buyerRef.length, "highest bid not accepted");
    }
    
    /// #sender: account-3
    function transactionShouldBeCompleted () public {
        address seller = TestsAccounts.getAccount(2);
        transactionCompleted(0, seller, 0);
        
        bytes memory offerRef = abi.encode(seller, 0);
        bytes memory buyRef = abi.encode(msg.sender, 0);
        
        Assert.equal(done[abi.encode(offerRef, buyRef)], true, "tx not completed");
    }
    
}