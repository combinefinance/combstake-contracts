pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CombToken.sol";


interface IMigratorChef {
    // Perform LP token migration from legacy UniswapV2 to CombSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // CombSwap must mint EXACTLY the same amount of CombSwap LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef is the master of Comb. He can make Comb and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once COMB is sufficiently
// distributed and the community can show to govern itself.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of COMBs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCombPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCombPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;          // Address of LP token contract.
        uint256 allocPoint;      // How many allocation points assigned to this pool. COMBs to distribute per block.
        uint256 lastRewardBlock; // Last block number that COMBs distribution occurs.
        uint256 accCombPerShare; // Accumulated COMBs per share, times 1e12. See below.
    }

    // The COMB TOKEN!
    CombToken public comb;
    // Maximum COMB tokens to be mined
    uint256 MAX_COMB_SUPPLY = 10000 ether;
    uint256 BLOCKS_PER_DAY = 6500;
    // COMB tokens created on first block.
    uint256 public rewardFirstBlock = 6153846150000000; // ~48 tokens/daily
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    mapping(address => bool) public lpTokenExistsInPool;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when COMB mining starts.
    uint256 public startBlock = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(CombToken _comb, uint256 _startBlock) public {
        comb = _comb;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function start() external onlyOwner {
        startBlock = _startBlock;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(startBlock != 0, 'Please start the contract first!');
        require(
            !lpTokenExistsInPool[address(_lpToken)],
            'MasterCheif: LP Token Address already exists in pool'
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accCombPerShare: 0
        }));
        lpTokenExistsInPool[address(_lpToken)] = true;
    }

    function updateLpTokenExists(address _lpTokenAddr, bool _isExists)
        external
        onlyOwner
    {
        lpTokenExistsInPool[_lpTokenAddr] = _isExists;
    }

    // Update the given pool's COMB allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(
            !lpTokenExistsInPool[address(newLpToken)],
            'MasterChef: New LP Token Address already exists in pool'
        );
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
        lpTokenExistsInPool[address(newLpToken)] = true;
    }

    function rewardOnBlock(uint256 _blockNumber) public view returns (uint256) {
        uint256 blocksPassed = _blockNumber.sub(startBlock);
        uint256 daysPassed = blocksPassed.div(BLOCKS_PER_DAY);
        uint256 _reward = rewardFirstBlock;
        while (daysPassed > 0) {
            _reward = rewardFirstBlock.mul(9999).div(10000);
            daysPassed = daysPassed.sub(1);
        }
        return _reward;
    }

    function rewardThisBlock() public view returns (uint256) {
        return rewardOnBlock(block.number);
    }

    // Return reward unclaimed reward since last block
    function getPendingReward(uint256 _fromBlock) public view returns (uint256) {
        uint256 blocksPassedAfter = block.number.sub(_fromBlock);
        uint256 reward = rewardOnBlock(_fromBlock).add(rewardThisBlock()).div(2).mul(blocksPassedAfter);

        uint256 totalCombSupply = comb.totalSupply();
        if (totalCombSupply.add(reward) > MAX_COMB_SUPPLY) {
            reward = MAX_COMB_SUPPLY.sub(totalCombSupply);
        }
        return reward;
    }

    // View function to see pending COMBs on frontend.
    function pendingComb(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCombPerShare = pool.accCombPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 pendingReward = getPendingReward(pool.lastRewardBlock);
            uint256 combReward = pendingReward.mul(pool.allocPoint).div(totalAllocPoint);
            accCombPerShare = accCombPerShare.add(combReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accCombPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 pendingReward = getPendingReward(pool.lastRewardBlock);
        uint256 combReward = pendingReward.mul(pool.allocPoint).div(totalAllocPoint);
        comb.mint(address(this), combReward);
        pool.accCombPerShare = pool.accCombPerShare.add(combReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for COMB allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCombPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeCombTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCombPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCombPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeCombTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCombPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe comb transfer function, just in case if rounding error causes pool to not have enough COMBs.
    function safeCombTransfer(address _to, uint256 _amount) internal {
        uint256 combBal = comb.balanceOf(address(this));
        if (_amount > combBal) {
            comb.transfer(_to, combBal);
        } else {
            comb.transfer(_to, _amount);
        }
    }
}
