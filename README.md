## Smart contract for the game weighted rock paper scissors

### Warning

I've personally deployed and tested this contract to see if it worked properly with every possible scenario. 
I still ask you to read the whole contract carefully while having some knowledge about ETH smart contracts and make tests in a safe environment before using it with real ETH.
If you still decide to deploy this contract you accept my lack of any responsibilities regarding what happens with the deployed contract.

### Weighted rock paper scissors:

It's just like rock paper scissors except a "weight" can be assigned to each of the three options.  
The weight determines how much wei a player has to bet in order to use said option, this should introduce some mind games to the standard game.  

### Example of how the weights and betting system works:
 * How much a person needs to bet in order to play = baseBet * weight of the chosen option
 * rockWeight = 1, paperWeight = 2, scissorsWeight = 3, baseBet = 1 Wei
 * Example of game 1:
 * If Player 1 users rock, they pay 1 Wei.
 * If Player 2 uses paper, they pay 2 Wei.
 * Player 2 wins, therefore they get 3 Wei.
 * Example of game 2 if baseBet = 2 instead of 1:
 * If Player 1 uses rock, they pay 2 Wei.
 * If Player 2 uses scissors, they pay 6 Wei.
 * Player 1 wins, therefore they get 8 Wei.

Please read the contract comments on top of each method for more informations.  
