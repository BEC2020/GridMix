
Instructions for Deployment
1. Compile & Deploy the token contract KWH on a testnet (not Remix's JSVM)
    * params:  ([], addr)
2. Deploy masterSLEC
    * params: (addr of governor, addr of token contract from step 1)
3. Open up the deployed instance.

4. Participants register as prosumers & consumers with the function **registe**r
    * the param in Remix says it is a tuple - it is really the struct participant which you would pass in in an array's format. 
    [address proconsumerID,
        bool canBuy 1,
        bool canSell 1,
        buySpecs buyerSpecs [2] // struct of specs of the equipment (currently it contains 1 uint)
        sellSpecs sellerSpecs [3] // struct of specs of the equipment  (currently it contains 1 uint)
        location loc [],
        uint8 zip 44178,
        uint8 exists 3]

    eg: ['0x09154c5540caB11e2f5AAb284c6AB5415f96E26B', 1,1,[2],[3],[6.465422,3.406448], 44178,3]
    eg: ['0x09154c5540caB11e2f5AAb284c6AB5415f96E26B', 1,1,[2],[3],88, 44178,3]
    eg: [0x09154c5540caB11e2f5AAb284c6AB5415f96E26B, 1,1,[2],[3],(6.465422,3.406448), 44178,3]

    ['0x09154c5540caB11e2f5AAb284c6AB5415f96E26B', 1,1,[2],[3], 44178,3]

4. Open a market with the function **openMarket**

5. Initial postings to develop trading cohorts - although the cohort is really the list appropriate sellers (see below).
   * prosumers use the function **offerEnergy** with the example params:

   * consumers use the function **askForEnergy** with the example params:

5. Consumers then will see who is an appropriate buyer with the **view** function **findAppropriateSellers**
   - currenly matching on...
   - returns an array
   - consumer will choose an offer in this array to bid on
   - this array contains...

6. A consumer then bids to a specific offer with the function **bidToOffer** with example params
 - 
8. Funds are sent to the contract by the consumer - that match the bid (bad UX but anyway)

7. The current highest bid is visible to other buyers in the cohort  -** which function?**

8. Market is closed by the grid

9. The highest bid wins with the function **acceptHighestBid** -> hit by prosumer

10. Losing Consumers get their funds back with the function **withdraw** -> hit by consumer

11. The prosumer at the given time turns on their energyStream and the consumer opens their energy input.

12. After the consumer had consumed, they tell the contract that their order has been fulfilled with **transactionCompleted**

13. Utility (DSO) can buy the remain energyOffers with the funciton **buyFromRemainingSellers**

14. Utility (DSO) can sell to the remain energyOffers with the funciton **sellToRemainingBuyers**
