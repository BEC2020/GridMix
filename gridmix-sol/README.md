# This folder contains the solidity files associated with GridMix

## gridmix.sol is the starter solidity file for transactive energy
It contains 2 contracts - ENR for minting the token and masterSLEC.

Also of note in this directory is the file **gridmix_test.sol**  which is the file for unit testing.

###Instructions for Deployment
1. Compile & Deploy the token contract ENR on a testnet (not Remix's JSVM)
    * params:  eg: [],"0x05854cA140caB11e2f5AAb284c6AB5415f96E26B"

2. Deploy masterSLEC

3. Open up the deployed instance.

3. Go to the **init** function
    * input the params: addr of governor, addr of token contract from step 1
    eg: 0x05854cA140caB11e2f5AAb284c6AB5415f96E26B,0x61941babd6b0642cc7820ce81d90bbcd94614ac9

4. Participants register as prosumers & consumers with the function **register**
        params:
        bool canBuy 
        bool canSell
        uint8 buyerSpecs
        uint8 sellerSpecs
        eg: true,true,"2","2"

4. The Governor opens a market with the function **openMarket**
    param: maxPrice - this is the price of energy on the commercial market (the price that this market cannot exceed). So input a number- e.g. **20**

5. Prosumers & Consumers post their desire to buy and sell.   
   * prosumers use the function **offerEnergy** 
        - price - e.g. **18** (needs to be less than the max price)
        - energy - is to be the amount of kWh energy e.g. **10**

   * consumers use the function **askForEnergy** with the example params:
        - price - e.g. **10** (needs to be less than the max price)
        - energy - is to be the amount of kWh energy

5. Before bidding can begin, the asks and offers need to be grouped so that the asks and offers are appropriate for each other.  This could mean that their locations too far from each other or that a specfic **ask** does not want mare energy that a specific **offer**. This sorting is done when Consumers use the **view** function **findAppropriateSellers**
    * the input param for this function is the index of the array of energyStreams (of Asks) that this consumer has registered
        - eg: 0   (for the 1st Ask of a buyer)
   - The function **findAppropriateSellers** currently will select all prosumers who have the same or more energy in their offer. 
   - The function returns an array like: 
   0:
tuple(address,uint256)[]: matches 0x05854cA140caB11e2f5AAb284c6AB5415f96E26B,0

   - consumer will choose an offer in this array to bid on
   - this array contains the seller's address (0x05854cA140caB11e2f5AAb284c6AB5415f96E26B above) and the index number of this offer in the array of the seller's energyStreams (0 above). 

6. A consumer then bids on a specific offer with the function **bidToOffer** with example params:
    - "0","0x05854cA140caB11e2f5AAb284c6AB5415f96E26B","0","12"
    - the seller's info is in the array that got returned above
    - the buyer's params are the id of the Ask and the price that you want to pay

8. Funds are sent from the **send** function in the token's contract (not in the masterSLEC contract) and are sent to the **SLEC contract**.  The funds are then held there in escrow.
   - The amount sent by the consumer must match their bid's amount. 
   - If this is the 1st bid to this offer or if it is a subsquent bid then it should be the amount that the bid was increased over this consumer's previous bid. 
   - The userdata is the hex encoded amount of the seller's address, and the consumer's bid ID and the seller's offer's ID. Use the **view** function **getReferenceBidToOffer** to generate the data and then paste that hex encoded data into this field.

8. Market is closed by the grid.

9. When the prosumer clicks the function **acceptHighestBid** the winner is selected.

10. Losing Consumers get their funds back by interacting with the **withdraw** function.

11. The prosumer at the given time releases their energy to the grid and the consumer opens their energy input.

12. After the consumer had consumed the energy, they tell the contract that their order has been fulfilled with **transactionCompleted**

13. Utility (DSO) can buy the remain energyOffers with the funciton **buyFromRemainingSellers**

14. Utility (DSO) can sell to the remain energyOffers with the funciton **sellToRemainingBuyers**
