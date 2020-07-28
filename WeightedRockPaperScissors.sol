pragma solidity ^0.5.10;

/**
 * A game of weighted rock paper scissors.
 * It's just like rock paper scissors except a "weight" can be assigned to each of the three options.
 * The weight determines how much wei a player has to bet in order to use said option, this should some introduce mind games to the standard game.
 * Please read the comments on top of each method for more informations.
 * 
 * Please note: 
 * if the opposing player refuses to continue playing 
 * (maybe because he somehow debugged your choice when you called the reveal method and noticed that since he would lose either way he'd rather lock the funds of both players in the contract)
 * after a week that the game has been "locked" (by having player2 join the game), you can withdraw the funds of BOTH players without having to wait for the opposing player's reveal anymore,
 * before you can do that though you must reveal your own choice first in order to avoid weird stalemates.
 * 
 * Please note 2:
 * baseBet in startGame is Wei.
 */
contract WeightedRockPaperScissors {
    struct GameSession 
    {
        address payable player1;
        bytes32 hiddenPlayer1Choice; //hiddenPlayer1Choice = keccak256(abi.encodePacked(uint8 player1Choice, bytes32 secret))
        uint8 player1Choice;
        uint player1Payment;
        bool isPlayer1ChoiceRevealed;
        
        address payable player2; 
        bytes32 hiddenPlayer2Choice;
        uint8 player2Choice;
        uint player2Payment;
        bool isPlayer2ChoiceRevealed;
        
        uint8[3] weights; //0 = rockWeight, 1 = paperWeight, 2 = scissorsWeight
        uint baseBet; //in Wei!
        
        bool isActive;
        uint gameLockedTime; //if >0 Player2 has joined the game and nobody can withdraw anymore
    }
    
    //mapping of gameSessions between player1 and player2
    //key = keccak256(abi.encodePacked(player1Address, player2Address))
    //player1Address can only have one GameSessions with player2Address at a given time 
    mapping (bytes32 => GameSession) public gameSessions; 
    
    event showWeightsAndBaseBet(uint8 rockWeight, uint8 paperWeight, uint8 scissorsWeight, uint baseBet);
    event announceWinner(uint8 winner, uint winnerAmount, uint loserAmount);
    
    constructor() public {
    }
    
/**
 * Starts a game of rock paper scissors between two players determined by their public address.
 * The person who starts the game by calling this function becomes Player1.
 * In order to start the game Player1 needs to place their choice and the Wei needed for their part in the bet.
 * 
 * Parameters:
 * 
 * 1) player2:
 * Public address of Player 2.
 * 
 * 2) rockWeight, paperWeight, scissorsWeight and baseBet:
 *  baseBet determines how much Wei each player will be betting.
 * 
 * Each of the three choices is weighted in terms of how much Wei the player needs to spend in order to use said choice.
 * Wei spent = baseBet * choice weight.
 * The choice with the lowest weight must have weight = 1.
 * 
 * Example of weights and baseBet:
 * rockWeight = 1, paperWeight = 2, scissorsWeight = 3, baseBet = 1 Wei
 * Example of game 1:
 * If Player 1 users rock, they pay 1 Wei.
 * If Player 2 uses paper, they pay 2 Wei.
 * Player 2 wins, therefore they get 3 Wei.
 * Example of game 2 if baseBet = 2 instead of 1:
 * If Player 1 uses rock, they pay 2 Wei.
 * If Player 2 uses scissors, they pay 6 Wei.
 * Player 1 wins, therefore they get 8 Wei.
 * 
 * 3) hiddenPlayer1Choice = keccak256(abi.encodePacked(uint8 choice, bytes32 secret)):
 * Player1's choice between rock, paper and scissors.
 * choice = 1 if rock.
 * choice = 2 if paper.
 * choice = 3 if scissors.
 * 
 * Since data in smart contracts is public the chosen choice parameter must be given as the hash obtainer from "keccak256(abi.encodePacked(choice, secret))" 
 * where secret is a secret only known by Player 1.
 * 
 * 4) Value of the transaction:
 * 
 * Since transactions are public, in order to hide player1's choice while they wait for Player2,
 * the Wei sent must be the same or higher as "baseBet * highest weight".
 * Example of weights and baseBet:
 * rockWeight = 1, paperWeight = 2, scissorsWeight = 3, baseBet = 2 Wei
 * Therefore the person who calls this function must send at least 2 * 3 = 6 Wei.
 * Failing to do so will let Player 2 understand which Player1's choice by just looking at their Wei transaction.
 * In order to prevent this scenario, the function will fail if Player 1 tries to start a game with a transaction that's less than the minimum required.
 * 
 */
    function startGame(
        address payable player2,
        uint8 rockWeight,
        uint8 paperWeight,
        uint8 scissorsWeight,
        uint baseBet, //in Wei !
        bytes32 hiddenPlayer1Choice
    )
        public
        payable
    {
        require(rockWeight == 1 || paperWeight == 1 || scissorsWeight == 1, "Please set one of the weights to 1");
        //Player1 can't create more than one GameSession with Player2 while a previous one is still active
        //otherwise the previous one will be overwritten
        bytes32 gameSessionKey = keccak256(abi.encodePacked(msg.sender, player2));
        //checks that there's no previous active GameSession
        require(gameSessions[gameSessionKey].isActive == false, 
        "A game session between these two players is already active and must finish before starting a new one."); 
        
        uint maxWeight = getMaxWeight(rockWeight, paperWeight, scissorsWeight);
        
        //the highest number we can get in this function is maxWeight * baseBet
        //we need to avoid a possible overflow
        uint avoidOverflow = 2**128-1;
        require(maxWeight < avoidOverflow, "The value of the weight is too high.");
        require(baseBet < avoidOverflow, "The value of the base bet is too high.");
        require(maxWeight * baseBet <= msg.value, "You need to transfer an amount of wei that's at least = 'base bet * max chosen weight'.");
        
        GameSession memory gameSession = GameSession({
            player1: msg.sender,
            hiddenPlayer1Choice: hiddenPlayer1Choice,
            player1Choice: 0,
            player1Payment: msg.value,
            isPlayer1ChoiceRevealed: false,
            
            player2: player2,
            hiddenPlayer2Choice: 0,  //0 = value not yet set, it will be when player2 joins the GameSession
            player2Choice: 0,
            player2Payment: 0,
            isPlayer2ChoiceRevealed: false,
            
            weights: [rockWeight,paperWeight,scissorsWeight],
            baseBet: baseBet,
            
            isActive: true,
            gameLockedTime: 0
        });
        
        gameSessions[gameSessionKey] = gameSession;
    }
    
    /**
     * A game can only be canceled if Player 2 hasn't joined the game yet.
     * Player 1 will get a refund.
     */
    function cancelGame(address player2) 
    public 
    {
        //check if the session exists
        bytes32 gameSessionKey = keccak256(abi.encodePacked(msg.sender, player2));
        GameSession storage session = gameSessions[gameSessionKey];
        require(session.isActive, "There's no active game session.");
        require(session.gameLockedTime == 0, "Player2 has joined the game and neither can withdraw anymore.");
        
        //refund while avoiding re-entrancy attacks
        uint refund = session.player1Payment;
        delete gameSessions[gameSessionKey];
        msg.sender.transfer(refund);
    }
    
    function partecipateAsPlayer2(
        address player1,
        bytes32 hiddenPlayer2Choice, 
        uint8 rockWeight, 
        uint8 paperWeight, 
        uint8 scissorsWeight
    ) 
    public 
    payable
    {
        bytes32 gameSessionKey = keccak256(abi.encodePacked(player1, msg.sender));
        GameSession storage session = gameSessions[gameSessionKey];
        require(session.gameLockedTime == 0, "Player2 has already joined.");
        require(session.isActive, "Player1 needs to start the game first."); 
        require(session.weights[0] == rockWeight && session.weights[1] == paperWeight && session.weights[2] == scissorsWeight,
        "The weights given don't match with the ones declared by Player1.");
        uint maxWeight = getMaxWeight(session.weights[0], session.weights[1], session.weights[2]);
        require(session.baseBet * maxWeight <= msg.value, 
        "You need to transfer an amount of wei that's at least = 'base bet * max chosen weight'.");
        
        session.hiddenPlayer2Choice = hiddenPlayer2Choice;
        session.player2Payment = msg.value;
        //Once Player2 joins the game nobody can cancel the game anymore
        session.gameLockedTime = now;
    }
    
    //each player calls this function to reveal their choice, once both have done so the game will declare a winner
    //playerType is needed to understand if the caller of the function is player 1 or player 2
    //playerType = 1 if player1, playerType = 2 if player2
    //choice = the choice originally made between rock (1), paper (2) and scissors (3)
    //secret = the secret originally chosen to encrypt the choice
    function revealChoice( uint8 playerType, address otherPlayer, uint8 choice, bytes32 secret) 
    public 
    {
        require(playerType == 1 || playerType == 2, "Type 1 if you're player 1 or type 2 if you're player 2.");

        if(playerType == 1)
        {
            revealPlayer1Choice(otherPlayer, choice, secret);
        }else
        {
            revealPlayer2Choice( otherPlayer, choice, secret);
        }
    }
    
    function revealPlayer1Choice(address player2, uint8 choice, bytes32 secret)
    private
    {
        bytes32 gameSessionKey = keccak256(abi.encodePacked(msg.sender, player2));
        GameSession storage session = gameSessions[gameSessionKey];
        require(!session.isPlayer1ChoiceRevealed, "You have already revealed your choice.");
        require(session.isActive, "There's no currently ongoing game."); 
        require(session.gameLockedTime > 0, "Player 2 hasn't joined yet."); 
        require(session.hiddenPlayer1Choice == keccak256(abi.encodePacked(choice, secret)), "Choice or secret are invalid.");
        
        session.player1Choice = choice;
        session.isPlayer1ChoiceRevealed = true;
        
        if(session.isPlayer2ChoiceRevealed){
            declareWinner(session);
        }
    }
    
    function revealPlayer2Choice(address player1, uint8 choice, bytes32 secret)
    private
    {
        bytes32 gameSessionKey = keccak256(abi.encodePacked(player1, msg.sender));
        GameSession storage session = gameSessions[gameSessionKey];
        require(!session.isPlayer2ChoiceRevealed, "You have already revealed your choice.");
        require(session.isActive, "There's no currently ongoing game."); 
        require(session.gameLockedTime > 0, "Player 2 hasn't joined yet."); 
        require(session.hiddenPlayer2Choice == keccak256(abi.encodePacked(choice, secret)), "Choice or secret are invalid.");
        
        session.player2Choice = choice;
        session.isPlayer2ChoiceRevealed = true;
        
        if(session.isPlayer1ChoiceRevealed){
            declareWinner(session);
        }
    }
    
    function declareWinner(GameSession storage session) 
    private
    {
        uint8 player1Choice = session.player1Choice;
        uint8 player2Choice = session.player2Choice;
        uint8 winner = 0;
        uint8 loserChoice;
        
        if(player1Choice == 2 && player2Choice == 1 
        || player1Choice == 3 && player2Choice == 2 
        || player1Choice == 1 && player2Choice == 3 
        || ((player1Choice >= 1 && player1Choice <= 4) && (player2Choice < 1 || player2Choice > 4)) //p1 is valid but p2 is not
        ){
            winner = 1;
            loserChoice = player2Choice;
        }
        else if (player2Choice >= 1 && player2Choice <= 4 && player2Choice != player1Choice) 
        {
            winner = 2;
            loserChoice = player1Choice;
        }
        
        getPrize(session, winner, loserChoice-1); //-1 because choices are 1,2,3 but array index is 0,1,2
    }
    
    function getPrize(GameSession storage session, uint8 winner, uint8 loserChoice) 
    private
    {
        address payable player1 = session.player1;
        address payable player2 = session.player2;
        uint player1Payment = session.player1Payment;
        uint player2Payment = session.player2Payment;
        uint baseBet = session.baseBet;
        uint8 loserWeight = session.weights[loserChoice];
        uint prize = baseBet * loserWeight;
        
        //game is over, avoid re-entrancy
        bytes32 gameSessionKey = keccak256(abi.encodePacked(player1, player2));
        delete gameSessions[gameSessionKey];
        
        if(winner == 1){
            player1Payment += prize;
            player2Payment -= prize;
            emit announceWinner(1, player1Payment, player2Payment);
        }else if(winner == 2){
            player2Payment += prize;
            player1Payment -= prize;
            emit announceWinner(2, player2Payment, player1Payment);
        }
        
        //draw or both invalid, refund
        player1.transfer(player1Payment);
        player2.transfer(player2Payment);
    }
    
    //If one player for some reason hasn't revealed their choice after a week the game got locked (player2 joined)
    //the other player can claim the prize by foirfeit where
    //prize = the entire payment of player 1 + the entire payment of player 2
    //playerType = 1 if player1, playerType = 2 if player2
    function claimForfeitedGame( uint8 playerType, address otherPlayer ) 
    public 
    {
        require(playerType == 1 || playerType == 2, "Type 1 if you're player 1 or type 2 if you're player 2.");
        bytes32 gameSessionKey;

        if(playerType == 1)
        {
            gameSessionKey = keccak256(abi.encodePacked(msg.sender, otherPlayer));
        }else
        {
            gameSessionKey = keccak256(abi.encodePacked(otherPlayer, msg.sender));
        }
        
        GameSession storage session = gameSessions[gameSessionKey];
        require(now > session.gameLockedTime + 1 weeks, "One week since Player2 has joined the game must pass before you can claim the prize by foirfeit.");
        
        if(playerType == 1)
        {
            require(session.isPlayer1ChoiceRevealed, "You must reveal your choice first.");  
            require(!session.isPlayer2ChoiceRevealed, "You shouldn't be able to read this."); 
        }else
        {
            require(session.isPlayer2ChoiceRevealed, "You must reveal your choice first.");
            require(!session.isPlayer1ChoiceRevealed, "You shouldn't be able to read this.");
        }
        uint prize = session.player1Payment + session.player2Payment;
        delete gameSessions[gameSessionKey];
        msg.sender.transfer(prize);
    }
    
    function getMaxWeight(uint8 rockWeight, uint8 paperWeight, uint8 scissorsWeight) 
    private pure returns (uint256 maxWeight)
    {
        maxWeight = rockWeight;
        if(paperWeight > maxWeight){
             maxWeight = paperWeight;
        }
        if(scissorsWeight > maxWeight){
            maxWeight = scissorsWeight;
        }
        return maxWeight;
    }
    
    function getWeightsAndBaseBet(address player1, address player2)
    public
    {
        bytes32 gameSessionKey = keccak256(abi.encodePacked(player1, player2));
        GameSession storage session = gameSessions[gameSessionKey];
        require(session.isActive, "Player1 needs to start the game first."); 
        uint8 rockWeight = session.weights[0];
        uint8 paperWeight = session.weights[1];
        uint8 scissorsWeight = session.weights[2];
        
        emit showWeightsAndBaseBet(rockWeight, paperWeight, scissorsWeight, session.baseBet);
    }
}
