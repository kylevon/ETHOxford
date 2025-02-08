// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interface for the program and update functions
interface IStateTransition {
    // Prog(j,w,t; st) - Returns (newState, payout)
    // j: party index triggering the contract
    // w: triggering witness (e.g. "exit" token)
    // t: time of trigger
    // st: current abstract state
    function prog(
        uint256 j,
        bytes calldata w,
        uint256 t,
        bytes calldata st
    ) external view returns (bytes memory newState, uint256 payout);

    // Update(j, u, t; st) - Returns new state
    // j: party index
    // u: witness tuple (b′, ψ, coins(bj))
    // t: time of trigger
    // st: current abstract state
    function update(
        uint256 j,
        bytes calldata u,
        uint256 t,
        bytes calldata st
    ) external view returns (bytes memory newState);
}

abstract contract DynamicStatefulContract {
    // Session identifier
    bytes32 public immutable sid;
    
    // Number of parties
    uint256 public immutable n;
    
    // Current abstract state - could be any data structure
    bytes public st;
    
    // Total coins available in contract
    uint256 public Q;
    
    // Abstract state transition functions
    IStateTransition public immutable stateTransition;
    
    // Event declarations
    event Initialized(bytes32 indexed sid, uint256 indexed j, bytes st, uint256 deposit);
    event StateUpdated(uint256 indexed j, bytes newState, uint256 payout);
    event ContractUpdated(uint256 indexed j, bytes newState);
    event ContractTerminated(address recipient);
    
    constructor(
        bytes32 _sid,
        uint256 _n,
        address _stateTransition,
        bytes memory _initialState
    ) {
        sid = _sid;
        n = _n;
        stateTransition = IStateTransition(_stateTransition);
        st = _initialState;
    }
    
    // Initialization phase - each party Pj deposits dj coins
    function initialize(bytes calldata initialState) external payable {
        // Convert msg.sender to party index j
        uint256 j = uint256(uint160(msg.sender));
        require(j > 0 && j <= n, "Invalid party index");
        
        // Accept deposit
        Q += msg.value;
        
        // Only set initial state if this is the first deposit
        if (st.length == 0) {
            st = initialState;
        }
        
        emit Initialized(sid, j, st, msg.value);
    }
    
    // Execution phase - trigger state transition
    function trigger(bytes calldata w) external {
        uint256 j = uint256(uint160(msg.sender));
        require(j > 0 && j <= n, "Invalid party index");
        
        // Get current time
        uint256 t = block.timestamp;
        
        // Call abstract program function Prog(j,w,t; st)
        (bytes memory newState, uint256 payout) = stateTransition.prog(j, w, t, st);
        
        // Verify payout is possible
        require(payout < Q, "Insufficient funds");
        
        // Update state and balance
        st = newState;
        Q -= payout;
        
        // Transfer payout
        payable(msg.sender).transfer(payout);
        
        emit StateUpdated(j, newState, payout);
        
        // Terminate if no funds left
        if (Q == 0) {
            emit ContractTerminated(msg.sender);
            // Instead of selfdestruct, we'll just emit an event
            // The contract will remain on chain but with Q = 0
        }
    }
    
    // Update function to add coins during execution
    function update(bytes calldata u) external payable {
        uint256 j = uint256(uint160(msg.sender));
        require(j > 0 && j <= n, "Invalid party index");
        
        // Get current time
        uint256 t = block.timestamp;
        
        // Call abstract update function Update(j, u, t; st)
        bytes memory newState = stateTransition.update(j, u, t, st);
        
        // Update state and balance
        st = newState;
        Q += msg.value;
        
        emit ContractUpdated(j, newState);
    }
} 