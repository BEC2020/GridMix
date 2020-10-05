pragma experimental ABIEncoderV2;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/utils/EnumerableMap.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/introspection/IERC1820Registry.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/token/ERC777/IERC777Recipient.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.2.0/contracts/token/ERC777/IERC777.sol";

contract masterSLEC is IERC777Recipient {
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    
    IERC777 token;
    
    constructor (address _grid, address _token) public {
        token = IERC777(_token);
        grid = _grid;
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }
    
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
        require(currentMarket.startTimestamp <= block.timestamp && currentMarket.endTimestamp > block.timestamp, "market is closed (time)");
        _;
    }
    
    modifier marketIsClosed () {
        require(!currentMarket.isOpen, "market is open");
        require(currentMarket.startTimestamp > block.timestamp && currentMarket.endTimestamp <= block.timestamp, "market is open (time)");
        _;
    }
    
    modifier deliverytimeIsInRange(energyStream memory _energy) {
        require(_energy.startDeliveryTimestamp >= currentMarket.startDeliveryTimestamp, "startDeliveryTimestamp out of range");
        require(_energy.endDeliveryTimestamp < currentMarket.endDeliveryTimestamp, "endDeliveryTimestamp out of range");
        _;
    }
    
    
    address private grid;
    
    // define energy units
    /*
    uint64 constant mWh = 1;
    uint64 constant  Wh = 1000 * mWh;
    uint64 constant kWh = 1000 * Wh;
    uint64 constant MWh = 1000 * kWh;
    */
    
    uint8 minBidIncrement = 10;
   
    struct buySpecs {
        uint id;
    }
    
    struct sellSpecs {
        uint id;
    }
    
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
    
    struct participant {
        address prosumerID; // prosumer or consumer or both
        bool canBuy; // has permission to buy
        bool canSell;  // has permission to sell
        buySpecs buyerSpecs; // struct of specs of the equipment
        sellSpecs sellerSpecs; // struct of specs of the equipment
        location loc; // longlat
        uint8 zip; // zip code - added in this version
        uint8 exists;
    }
  
     // energyStream is for requesting and offering energy
    struct energyStream {
        address addr; // sellerProducer's public key
        uint64 timestamp; // timestamp for when the energy offer was submitted
        uint startDeliveryTimestamp;
        uint endDeliveryTimestamp;
        uint price; // sellerProducer price (bid) vs market price
        uint64 energy;  // sellerProducer energy to sell - amount of kw/h?
    }
    
    struct streamRef {
        address addr;
        uint id;
    }
    
    mapping(address => participant) public participants;
    
    mapping(address => energyStream[]) public sellEnergy_map;
    EnumerableMap.UintToAddressMap private sellEnergy_list;
    
    mapping(address => energyStream[]) public buyEnergy_map;
    
    mapping(bytes => streamRef[]) bids;
    mapping(bytes => uint) bids_acquired;
    
    mapping(bytes => bytes) accepted;
    mapping(bytes => bool) done;
    
    market currentMarket;
    
    /**
     * @dev Called when the payment has been received by the prosumer
     * @param operator need more def 
     * @param from the buyer
     * @param to the seller
     * @param amount how much was received
     * @param userData need more def
     * @param operatorData need more def
     */
    function tokensReceived (
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external override {
        // TODO check if this the right token contract.
        // userData is concatenation of seller , idOffer, idAsk
        bytes memory ref = abi.encodePacked(userData, from);
        bids_acquired[ref] += amount;
    }
    
        /**
     * @dev Opens a Market.  The market is a period where prosumers and consumers can 
     * try buy and sell to each other. It can only be opened by the organizer of this market - the "grid".
     * @param startTimestamp The time that the market opens
     * @param endTimestamp The time that the market closes
     * @param startDeliveryTimestamp The time that energy can start to be delivered - wait - is this necessary in this function?  YEs a market is for energy that is to be delivered during a certain period.
     * @param endDeliveryTimestamp The time that energy finishes flowing
     * @param maxPrice The current cost of 1 kWh on the commercial market (not this prosumer/consumer market)
     */
     function openMarket (
                uint startTimestamp, 
                uint endTimestamp, 
                uint startDeliveryTimestamp, 
                uint endDeliveryTimestamp,
                uint maxPrice) public 
    {
        require(msg.sender == grid, "not the grid");
        require(!currentMarket.isOpen, "market already opened");
        currentMarket.id = block.timestamp;
        currentMarket.startTimestamp = startTimestamp;
        currentMarket.endTimestamp = endTimestamp;
        currentMarket.startDeliveryTimestamp = startDeliveryTimestamp;
        currentMarket.endDeliveryTimestamp = endDeliveryTimestamp;
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
    }
    
    /**
     * @dev Registers a participant into the GridMix 
     * currently a participant self registering
     * @param member is a consumer or prosumer joining this system
     */
    function register(participant memory member) public {
        require(participants[msg.sender].exists == 1, "already registerd");
        participants[msg.sender].prosumerID = msg.sender;
        participants[msg.sender].exists = 1;
        participants[msg.sender] = member;
    }
    
    /**
     * @dev UnRegisters a participant from the GridMix 
     * currently a participant is removing themselves
     */
    function unregister() public {
        delete participants[msg.sender];
    }

    /**
     * @dev A participant registers a desire to SELL an energy stream in a market
     * @param _energy The energyStream contains amount of kWh, the time that the energy is going to be available, etc
     */
    function offerEnergy(energyStream memory _energy) isParticipant(msg.sender) marketIsOpen() streamOwner(_energy) public {
        require(participants[msg.sender].canSell, "participant can't sell");
        require(_energy.startDeliveryTimestamp >= currentMarket.startDeliveryTimestamp, "startDeliveryTimestamp out of range");
        require(_energy.endDeliveryTimestamp < currentMarket.endDeliveryTimestamp, "endDeliveryTimestamp out of range");
        require(_energy.price <= currentMarket.maxPrice, "price to high");
        
        sellEnergy_map[msg.sender].push(_energy);
        uint newIndex = EnumerableMap.length(sellEnergy_list);
        EnumerableMap.set(sellEnergy_list, newIndex, msg.sender);
    
        currentMarket.offerEnergyCounter++;
    }
    
    /**
     * @dev A participant registers a desire to buy an energy stream in a market
     * @param _energy contains the amount of energy and when it is desired
     */
    function askForEnergy(energyStream memory _energy) isParticipant(msg.sender) marketIsOpen() deliverytimeIsInRange(_energy) streamOwner(_energy) public {
        require(participants[msg.sender].canBuy, "participant can't buy");
        require(_energy.price <= currentMarket.maxPrice, "price to high");
        
        buyEnergy_map[msg.sender].push(_energy);
    }
    
    /**
     * @dev A Consumer bidding to buy energy from a specific seller's stream. 
     * This happens after the list of appropriate market cohorts (sellers and buyers who are allowed to sell to each other) -has been generated.  Does a cohort need an ID?
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
        bytes memory offerRef = abi.encodePacked(seller, idOffer);
        streamRef memory b;
        b.addr = msg.sender;
        b.id = idAsk;
        bids[offerRef].push(b);
    }
    
    /**
     * @dev When the market is closed this function is called and the highest offer wins.  
     * This function is triggered by the market closing. Or should it be a txn by the Prosumer of that Offer?
     * @param idOffer the ID of the highest offer?
     * @return highestStream the streamRef of the 
     */
    function acceptHighestBid (uint idOffer) isParticipant(msg.sender) marketIsClosed() public returns(streamRef memory highestStream) {
        bytes memory offerRef = abi.encodePacked(msg.sender, idOffer);
        require(bids[offerRef].length != 0, "There is no bid");
        require(accepted[offerRef].length == 0, "a bid has already been accepted");
        require(block.timestamp < currentMarket.startDeliveryTimestamp, "delivery has already started");
        
        uint price = 0;
        for (uint k = 0 ; k < bids[offerRef].length; k++) {
            streamRef memory ref = bids[offerRef][k];
            bytes memory bid_acquired = abi.encodePacked(msg.sender, idOffer, ref.id, ref.addr);
            if (price < bids_acquired[bid_acquired]) {
                price = bids_acquired[bid_acquired];
                highestStream = ref;
            }
        }
        accepted[offerRef] = abi.encodePacked(highestStream.addr, highestStream.id);
    }
    
    /**
     * @dev YANN - we need to review and is called by the msg.sender who in this case is...
     * @param seller the addr of the seller  
     * @param idOffer the energy offer that is getting sold 
     * @param idAsk the id of the buyer's bid
     */
    function withdraw(address seller, uint idOffer, uint idAsk) public {
        bytes memory bid_ref = abi.encodePacked(seller, idOffer, idAsk, msg.sender);
        
        if (bids_acquired[bid_ref] > 0) {
            token.send(msg.sender, bids_acquired[bid_ref], "");
            delete bids_acquired[bid_ref];
        }
    }
    
    /**
     * @dev After the market is closed, the DSO can buy the remain capacity 
     * @param buyerItems an array of streamRefs  
     */
    function sellToRemainingBuyers (streamRef[] memory buyerItems) marketIsClosed() public {
        require(msg.sender == grid, "only grid utility can call closeSurplus");
        require(block.timestamp < currentMarket.startDeliveryTimestamp, "delivery has already started");
        // TODO check if buyerItems are still opened
        
        // the grid sell to the remaining buyer.
        uint id = 0;
        for (uint k = 0; k < buyerItems.length; k++) {
            bytes memory gridRef = abi.encodePacked(grid, id);
            bytes memory buyRef = abi.encodePacked(grid, buyerItems[k].addr);
            accepted[gridRef] = buyRef;
        }
        // TODO money transfer goes offchain for the moment
    }
    
    /**
     * @dev After the market is closed, the DSO can sell to the remain consumers 
     * @param sellerItems[] an array of streamRefs  
     */
    function buyFromRemainingSellers (streamRef[] memory sellerItems) marketIsClosed() public {
        require(msg.sender == grid, "only grid utility can call closeSurplus");
        require(block.timestamp < currentMarket.startDeliveryTimestamp, "delivery has already started");
        // TODO check if sellerItems are still opened
        
        // the grid buy from the remaining sellers.
        uint id = 0;
        for (uint k = 0; k < sellerItems.length; k++) {
            bytes memory gridRef = abi.encodePacked(grid, id);
            bytes memory sellRef = abi.encodePacked(grid, sellerItems[k].addr, sellerItems[k].addr);
            accepted[sellRef] = gridRef;
        }
        // TODO money transfer goes offchain for the moment
    }
    
    /* 
     * This is called buy the seller (either the grid or the local entity)
     * when the buyer has received the energy.
     *
    */
    /**
     * @dev  
     * @param idOffer the id created
     * @param seller the seller's address
     * @param idAsk the ID of the Ask
     */
    function transactionCompleted (uint idOffer, address seller, uint idAsk) isParticipant(msg.sender) marketIsClosed() public {
        bytes memory offerRef = abi.encodePacked(msg.sender, idOffer);
        bytes memory buyRef = abi.encodePacked(msg.sender, idAsk);
        require(accepted[offerRef].length == 0, "no accepted bid");
        
        // release the deposit to the producer
        // TODO there is no consistency between the price define in the bid and the amount locked in the contract
        bytes memory bid_ref = abi.encodePacked(seller, idOffer, idAsk, msg.sender);
        if (bids_acquired[bid_ref] != 0) {
            token.send(seller, bids_acquired[bid_ref], "");
            delete bids_acquired[bid_ref];
        }
        done[abi.encodePacked(offerRef, buyRef)] = true;
    }
    
    /**
     * @dev  findAppropriateSellers is called by the buyers to loop through the sellers offers to get a list of appropriate sellers.
     * it is a view function
     * @param id The ID of the buyer who calls this function... or is this the ID
     * @return matches the array of all the sellEnergy that matches the buyEnergy for the current msg.sender
     */
    function findAppropriateSellers (uint id) view public isParticipant(msg.sender) marketIsOpen() returns (streamRef[] memory matches) {
        // This should return all the sellEnergy that matches the buyEnergy for the current msg.sender
        energyStream storage checking = buyEnergy_map[msg.sender][id];
        
        matches = new streamRef[](currentMarket.offerEnergyCounter);
        uint counter = 0;
        
        uint length = EnumerableMap.length(sellEnergy_list);
        for (uint k = 0; k < length; k++) {
            (uint index, address seller) = EnumerableMap.at(sellEnergy_list, k);
            energyStream[] memory toSell = sellEnergy_map[seller];
            for (uint i = 0; i < toSell.length; i++) {
                energyStream memory currentSellEnergy = toSell[i];
                
                if (currentSellEnergy.startDeliveryTimestamp <= checking.startDeliveryTimestamp &&
                    currentSellEnergy.endDeliveryTimestamp > checking.endDeliveryTimestamp &&
                    checking.energy <= currentSellEnergy.energy) {
                        streamRef memory ref;
                        ref.addr = seller;
                        ref.id = i;
                        matches[counter] = ref;
                        counter++;        
                    }
            }
        }
    }
}
