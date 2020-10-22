pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/utils/EnumerableMap.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/introspection/IERC1820Registry.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/token/ERC777/IERC777Recipient.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/token/ERC777/ERC777.sol";

// SECTION: MINTING ENR TOKEN  
contract ENR is ERC777 {
    constructor (address[] memory operators, address governor) ERC777("energy", "ENR", operators) public {
        // mint 1,000,000 ENR tokens and send to the governor
        _mint(governor, 1000000000000000000000000, bytes(""), bytes(""));
    }
}

contract masterSLEC is IERC777Recipient {
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    // EnumerableMap is used to be able to loop over a mapping
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
 
    IERC777 token;
    
    // SECTION: CONSTRUCTOR & INIT FUNCTIONS  
     /** 
     * @dev Create a new instance of masterSLEC - to be used for creating energy markets.
     */
    constructor () public {
        
    }

     /** 
     * @dev Initialize the contract by filling the address of the grid and the address of the token's contract.
     * @param _grid the address of the governor
     * @param _token the address of the token's contract
     */
    function init(address _grid, address _token) public {
        address[] memory operators;
        token = IERC777(_token);
        grid = _grid;
        // this if statment is here for running the gridMix_test.sol file
        // if this is not a test the erc1820.setInterfaceImplementer is set - 
        // this sets the type of tokens that this contract can receive
        if (_token != address(0)) {
            _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));    
        }
    }

    // SECTION: MODIFIERS 
    modifier streamOwner (energyStream memory _energy) {
        require(_energy.addr == msg.sender, "must be stream owner");
        _;
    }
    
    modifier isParticipant (address _address) {
        require(participants[msg.sender].exists == 1, "not registered yet");
        _;
    }
    
    modifier marketIsOpen () {
        require(currentMarket.isOpen, "market is closed");
        // require(currentMarket.startTimestamp <= block.timestamp && currentMarket.endTimestamp > block.timestamp, "market is closed (time)");
        _;
    }
    
    modifier marketIsClosed () {
        require(!currentMarket.isOpen, "market is open");
        // require(currentMarket.startTimestamp > block.timestamp && currentMarket.endTimestamp <= block.timestamp, "market is open (time)");
        _;
    }
    
    // currently this modifier's require statements are commented out
    modifier deliverytimeIsInRange(energyStream memory _energy) {
        // require(_energy.startDeliveryTimestamp >= currentMarket.startDeliveryTimestamp, "startDeliveryTimestamp out of range");
        // require(_energy.endDeliveryTimestamp < currentMarket.endDeliveryTimestamp, "endDeliveryTimestamp out of range");
        _;
    }

    // SECTION: STATE VARIABLES
    // the grid the governor
    address private grid;
    
    // define energy units
    /*
    uint64 constant mWh = 1;
    uint64 constant  Wh = 1000 * mWh;
    uint64 constant kWh = 1000 * Wh;
    uint64 constant MWh = 1000 * kWh;
    */
    
    // the minimum amount a bid can be incremented
    uint8 minBidIncrement = 10;
   
    struct buySpecs {
        uint id;
    }
    
    struct sellSpecs {
        uint id;
    }
    
    // currently not being used as part of a participant but should eventually be incorporated    
    struct location {
        uint long;
        uint lat;
    }
    
    struct market {
        uint id;
        uint startTimestamp;
        uint endTimestamp;
        uint startDeliveryTimestamp;
        uint endDeliveryTimestamp;
        bool isOpen;
        uint offerEnergyCounter;
        uint maxPrice;
    }
    
    // a participant is a buyer or a seller of energy
    struct participant {
        address participantID; // prosumer or consumer or both
        bool canBuy; // has permission to buy
        bool canSell;  // has permission to sell
        buySpecs buyerSpecs; // struct of specs of the equipment
        sellSpecs sellerSpecs; // struct of specs of the equipment
        uint8 exists; // has been registered
    }
  
     // energyStream is for BOTH requesting and offering energy
    struct energyStream {
        address addr; // the stream's owner
        uint startDeliveryTimestamp;
        uint endDeliveryTimestamp;
        uint price; // price desired
        uint64 energy;  // amount of energy to buy or sell
    }
    
    struct streamRef {
        address addr;
        uint id;
    }
    
    // the list of participant structs indexed by address
    mapping(address => participant) public participants;
    
    // the list of energyStream structs that are for sale - indexed by the address of the stream's owner
    mapping(address => energyStream[]) public sellEnergy_map;
    // sellEnergy_list is needed to be able to loop over the the map sellEnergy_map
    EnumerableMap.UintToAddressMap private sellEnergy_list;
    
    // the list of energyStream structs documenting a desire to buy - indexed by the address of the stream's owner
    mapping(address => energyStream[]) public buyEnergy_map;
    
    mapping(bytes => streamRef[]) public bids;
    // when a bid has been accepted it goes into this mapping until the delivery of energy has been confirmed
    mapping(bytes => uint) public bids_acquired; // bytes is concatenation of seller - buyer - id offer - id ask
    
    mapping(bytes => bytes) public accepted;
    // after delivery has been confirmed the sale is recorded here
    // bytes is an encoding of offerRef, buyRef
    mapping(bytes => bool) public done;
    
    // the struct of the currentMarket
    market currentMarket;
    
    //SECTION: VIEW FUNCTION: GET THE TOKEN'S ADDRESS
    function getTokenAddress () view public returns (address) {
        return address(token);
    }

    //SECTION: RECEIVING TOKENS 
    /**
     * @dev Called when the payment has been received by the contract
     * @param operator in this case usually an empty array [] 
     * @param from the buyer
     * @param to the seller
     * @param amount how much was received
     * @param userData this is the info that contains the id of the offer, the id of the ask, and the seller's address - it is constructed by getReferenceBidToOffer
     * @param operatorData in the contract is not used
     */
    function tokensReceived (
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external override {
       
        require(msg.sender == address(token) || address(0) == address(token), "only ENR allowed");
        
        // decoding from the userData - the idAsk, the idOffer and the sellerAddress
        (uint idAsk, uint idOffer, address sellerAddress) = abi.decode(userData, (uint, uint, address));
        
        // encoding the ref# to be added to the bids_acquired array
        bytes memory ref = abi.encode(sellerAddress, from, idOffer, idAsk);
        bids_acquired[ref] += amount;
    }
    
    //SECTION: OPENING/CLOSING A MARKET  
    /**
    * @dev Opens a Market.  The market is a period where prosumers and consumers can try buy and sell to each other. It can only be opened by the grid.
    * @param maxPrice The maximum amount someone can bid or offer.  Should eventually be aligned with the price on the commercial market.
    */
     function openMarket (
                // uint startTimestamp, 
                // uint endTimestamp, 
                // uint startDeliveryTimestamp, 
                // uint endDeliveryTimestamp,
                uint maxPrice) public 
    {
        require(msg.sender == grid, "not the grid");
        require(!currentMarket.isOpen, "market already opened");
        currentMarket.id = block.timestamp;
        currentMarket.startTimestamp = block.timestamp;
        // currentMarket.endTimestamp = block.timestamp + 10 minutes;
        // currentMarket.startDeliveryTimestamp = block.timestamp + 10 minutes;
        // currentMarket.endDeliveryTimestamp = block.timestamp + 10 minutes + 5 minutes;
        currentMarket.isOpen = true;
        currentMarket.maxPrice = maxPrice;
        currentMarket.offerEnergyCounter = 0;
    }
    
    /**
     * @dev Closes a Market. It can only be closed by the organizer of this market - the "grid"
     */
    function closeMarket () public {
        require(msg.sender == grid, "not the grid");
        currentMarket.isOpen = false;
        currentMarket.endTimestamp = block.timestamp;
    }
    
    //SECTION: REGISTERING / UNREGISTERING PARTICIPANTS
    /**
     * @dev Registers a participant into the GridMix 
     * currently a participant self registering
     * @param prosumer Is the registrant a prosumer?
     * @param consumer Is the registrant a prosumer?
     * @param buyerSpec A number corresponding to their equipment
     * @param sellerSpec A number corresponding to their equipment
     */
    function register(bool prosumer, bool consumer, uint8 buyerSpec, uint8 sellerSpec) public {
        require(participants[msg.sender].exists == 0, "already registerd");
        participant memory newParticipant;
        newParticipant.participantID = msg.sender;
        newParticipant.canSell = prosumer;
        newParticipant.canBuy = consumer;
        newParticipant.buyerSpecs.id = buyerSpec;
        newParticipant.sellerSpecs.id = sellerSpec;
        newParticipant.exists = 1;
        participants[msg.sender] = newParticipant;
    }
    
    /**
     * @dev UnRegisters a participant from GridMix 
     * currently a participant is removing themselves
     */
    function unregister() public {
        delete participants[msg.sender];
    }

    //SECTION: INITIAL OFFERS & ASKS 
    /**
     * @dev A participant registers a desire to SELL an energy stream in a market. Should eventually contain the delivery window - currently the delivery is set by the market.
     * @param price the desired price to sell at - must be less than the commercial market price
     * @param energy the amount of energy to be sold
     */
    function offerEnergy(uint price, uint64 energy) isParticipant(msg.sender) marketIsOpen() public {
        require(participants[msg.sender].canSell, "participant can't sell");
        // require(_energy.startDeliveryTimestamp >= currentMarket.startDeliveryTimestamp, "startDeliveryTimestamp out of range");
        // require(_energy.endDeliveryTimestamp < currentMarket.endDeliveryTimestamp, "endDeliveryTimestamp out of range");
        require(price <= currentMarket.maxPrice, "price to high");
        
        // make an energyStream to add the params to
        energyStream memory stream;
        stream.addr = msg.sender;
        // stream.startDeliveryTimestamp = currentMarket.startDeliveryTimestamp;
        // stream.endDeliveryTimestamp = currentMarket.endDeliveryTimestamp;
        stream.price = price;
        stream.energy = energy;
        
        // push this stream onto the array of energyStreams of stream's owner's address located in the sellEnergy_map
        sellEnergy_map[msg.sender].push(stream);
        // get the length of the sellEnergy_list
        uint newIndex = EnumerableMap.length(sellEnergy_list);
        // prep the sellEnergy_list so it can be looped over
        EnumerableMap.set(sellEnergy_list, newIndex, msg.sender);
        // updating offerEnergyCounter for the currentMarket - a market struct
        currentMarket.offerEnergyCounter++;
    }
    
    /**
     * @dev A participant registers a desire to buy an energy stream in a market. Should eventually contain the delivery window desired.
     * @param price the amount desired to pay
     * @param energy the amount of energy desired to purchase
     */
    function askForEnergy(uint price, uint64 energy) isParticipant(msg.sender) marketIsOpen() public {
        require(participants[msg.sender].canBuy, "participant can't buy");
        require(price <= currentMarket.maxPrice, "price to high");
        
        // make an energyStream to add the params to
        energyStream memory stream;
        stream.addr = msg.sender;
        // stream.startDeliveryTimestamp = currentMarket.startDeliveryTimestamp;
        // stream.endDeliveryTimestamp = currentMarket.endDeliveryTimestamp;
        stream.price = price;
        stream.energy = energy;
        
        // push this stream onto the array of energyStreams of stream's owner's address located in the buyEnergy_map
        buyEnergy_map[msg.sender].push(stream);
    }
    
    //SECTION: FIND APPROPRIATE SELLERS 
     /**
     * @dev  findAppropriateSellersTx a non-payable helper function - is just like findAppropriateSellers but creates a txn so it can be debugged
     * @param id The ID of the buyer who calls this function... or is this the ID
     * @return matches the streamRef array of the matched streams
     */  
    function findAppropriateSellersTx (uint id) public isParticipant(msg.sender) marketIsOpen() returns (streamRef[] memory matches) {
        return findAppropriateSellers(id);
    }
    
    
    /**
     * @dev  findAppropriateSellers is called by the buyers to loop through the sellers offers to get a list of appropriate sellers.
     * it is a view function
     * @param id The index of the array of energyStreams (of Asks) of this consumer 
     * @return matches the array of the energyStreams being sold that match buyer based on delivery period & quantity
     */
    function findAppropriateSellers (uint id) view public isParticipant(msg.sender) marketIsOpen() returns (streamRef[] memory matches) {
        // This should return all the sellEnergy that matches the buyEnergy for the current msg.sender
        energyStream storage checking = buyEnergy_map[msg.sender][id];
        
        matches = new streamRef[](currentMarket.offerEnergyCounter);
        uint counter = 0;
        // preparing to loop through the EnumerableMap of the sellEnergy_list
        uint length = EnumerableMap.length(sellEnergy_list);
        for (uint k = 0; k < length; k++) {
            // get the seller address of each seller ( index not used)
            (uint index, address seller) = EnumerableMap.at(sellEnergy_list, k);
            // retrieve the array of energyStreams 
            energyStream[] memory toSell = sellEnergy_map[seller];
            // loop over this toSell array of energyStreams
            for (uint i = 0; i < toSell.length; i++) {
                // current energyStream in the loop held in currentSellEnergy
                energyStream memory currentSellEnergy = toSell[i];
                
                // check that the delivery begin & end period matches the buyers && that the sell amount is <= to the buyer's ask in checking.energy
                if (
                    // currentSellEnergy.startDeliveryTimestamp <= checking.startDeliveryTimestamp &&
                    // currentSellEnergy.endDeliveryTimestamp >= checking.endDeliveryTimestamp &&
                    checking.energy <= currentSellEnergy.energy) {
                        // if conditions are met make a ref - a streamRef containing the seller's addr & the index of this offer (in the seller's array of energyStream[] called toSell)
                        streamRef memory ref;
                        ref.addr = seller;
                        ref.id = i;
                        // add to an array of matches for this buyer
                        matches[counter] = ref;
                        counter++;   
                        // return matches (return of matches is declared in the return statement above)     
                    }
            }
        }
    }

    //SECTION: BID TO AN OFFER 
    /**
     * @dev A Consumer bidding to buy energy from a specific seller's stream.
     * @param idAsk the ID of this Ask for energy
     * @param seller the address of the seller
     * @param idOffer  the id of the Offer that we are bidding to
     * @param price the price that we are offering
     */
    function bidToOffer (uint idAsk, address seller, uint idOffer, uint price) isParticipant(msg.sender) marketIsOpen() public {
        require(buyEnergy_map[msg.sender].length > 0, "no ask from this buyer");
        require(buyEnergy_map[msg.sender][idAsk].addr == msg.sender, "ask doesn't exist");
        require(sellEnergy_map[seller].length > 0, "no offer from this seller");
        require(sellEnergy_map[seller][idOffer].addr == seller, "offer doesn't exist");
        require(price <= currentMarket.maxPrice, "price to high");
        
        if (price != 0 && buyEnergy_map[msg.sender][idAsk].price + minBidIncrement <= price) {
            // check if the price is not to high compared with the market price
            buyEnergy_map[msg.sender][idAsk].price = price;    
        }
        
        // encode the seller's info & offer info to create an ID
        bytes memory offerRef = abi.encode(seller, idOffer);
        streamRef memory b;
        b.addr = msg.sender;
        b.id = idAsk;
        // add it to the bids mapping with the key being the offerRef
        bids[offerRef].push(b);
    }
    
    //SECTION: ENCODE HELPER FUNCTION
     /**
     * @dev  create the ref # of a bid to offer
     * @param idAsk The ID of the energy ask
     * @param idOffer The ID of the energy offer
     * @param seller the address of the seller
     * @return ref - the encoded ref #
     */ 
    function getReferenceBidToOffer(uint idAsk, uint idOffer, address seller) public view returns (bytes memory ref) {
        ref = abi.encode(idOffer, idAsk, seller);
    }

    //SECTION: CHOOSING THE WINNER 
    /**
     * @dev When the market is closed this function should be called by the seller to choose the highest bid in an Ask.   
     * @param idOffer the ID of the Offer stream
     * @return highestStream the streamRef of the highest bidder
     */
      function acceptHighestBid (uint idOffer) isParticipant(msg.sender) marketIsClosed() public returns(streamRef memory highestStream) {
        // encode the seller's address & their id to get the offerRef
        bytes memory offerRef = abi.encode(msg.sender, idOffer);
        // make sure the bid exists, the offer has not yet been accepted and that delivery has not already started
        require(bids[offerRef].length != 0, "There is no bid");
        require(accepted[offerRef].length == 0, "a bid has already been accepted");
        // require(block.timestamp < currentMarket.startDeliveryTimestamp, "delivery has already started");
        
        uint price = 0;
        for (uint k = 0 ; k < bids[offerRef].length; k++) {
            streamRef memory ref = bids[offerRef][k];
            bytes memory bid_acquired = abi.encode(msg.sender, ref.addr, idOffer, ref.id);
            if (price < bids_acquired[bid_acquired]) {
                price = bids_acquired[bid_acquired];
                highestStream = ref;
            }
        }
        accepted[offerRef] = abi.encode(highestStream.addr, highestStream.id);
        // return highestStream
    }
    
    //SECTION: RETURN THE LOSER'S FUNDS
    /**
     * @dev For a buyer to withdraw funds associated with a bid.  Should be used for losing bids and called by a losing buyer.
     * @param seller the addr of the seller  
     * @param idOffer the energy offer that is getting sold 
     * @param idAsk the id of the buyer's bid
     */
     // It is not limited be being called while the market is closed
    function withdraw(address seller, uint idOffer, uint idAsk) public {
        // recreate the ref id for this bid
        bytes memory bid_ref = abi.encodePacked(seller, msg.sender, idOffer, idAsk);
        // check if this bid for this energyStream is in the bids_acquired array
        if (bids_acquired[bid_ref] > 0) {
            // return the funds buyer
            // this if is needed for the unit test
             if (address(0) != address(token))  token.send(msg.sender, bids_acquired[bid_ref], "");
            // delete from the array
            delete bids_acquired[bid_ref];
        }
    }
    
    //SECTION: DELIVERY FULFILLED - TRANSACTION COMPLETED 
    /**
     * @dev This function is hit by the consumer when their Ask has been fulfilled. 
     * @param idOffer the id created
     * @param seller the seller's address
     * @param idAsk the ID of the Ask
     */
    function transactionCompleted (uint idOffer, address seller, uint idAsk) isParticipant(msg.sender) marketIsClosed() public {
        bytes memory offerRef = abi.encode(seller, idOffer);
        bytes memory buyRef = abi.encode(msg.sender, idAsk);
        require(accepted[offerRef].length != 0, "no accepted bid");
        
        // release the deposit to the producer
        // TODO there is no consistency between the price define in the bid and the amount locked in the contract
        bytes memory bid_ref = abi.encode(seller, msg.sender, idOffer, idAsk);
        if (bids_acquired[bid_ref] != 0) {
            if (address(0) != address(token)) token.send(seller, bids_acquired[bid_ref], "");
            delete bids_acquired[bid_ref];
        }
        done[abi.encode(offerRef, buyRef)] = true;
    } 

    //SECTION: CLEAN UP INVENTORY OF OFFERS & ASKS  

    /**
     * @dev After the market is closed, the DSO can sell to the remain consumers 
     * @param sellerItems[] an array of streamRefs  
     */
    function buyFromRemainingSellers (streamRef[] memory sellerItems) marketIsClosed() public {
        // require(msg.sender == grid, "only grid utility can call closeSurplus");
        // require(block.timestamp < currentMarket.startDeliveryTimestamp, "delivery has already started");
        // // TODO check if sellerItems are still opened
        
        // // the grid buy from the remaining sellers.
        // uint id = 0;
        // for (uint k = 0; k < sellerItems.length; k++) {
        //     bytes memory gridRef = abi.encodePacked(grid, id);
        //     bytes memory sellRef = abi.encodePacked(grid, sellerItems[k].addr, sellerItems[k].addr);
        //     accepted[sellRef] = gridRef;
        // }
        // TODO money transfer goes offchain for the moment
    }


    /**
     * @dev After the market is closed, the DSO can buy the remain capacity 
     * @param buyerItems an array of streamRefs  
     */
    function sellToRemainingBuyers (streamRef[] memory buyerItems) marketIsClosed() public {
        // require(msg.sender == grid, "only grid utility can call closeSurplus");
        // require(block.timestamp < currentMarket.startDeliveryTimestamp, "delivery has already started");
        // // TODO check if buyerItems are still opened
        
        // // the grid sell to the remaining buyer.
        // uint id = 0;
        // for (uint k = 0; k < buyerItems.length; k++) {
        //     bytes memory gridRef = abi.encodePacked(grid, id);
        //     bytes memory buyRef = abi.encodePacked(grid, buyerItems[k].addr);
        //     accepted[gridRef] = buyRef;
        // }
        // TODO money transfer goes offchain for the moment
    }
    
}
