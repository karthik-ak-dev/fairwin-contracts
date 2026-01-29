# Changelog

## [2.0.1] - 2026-01-28

### Security Improvements

#### Added Emergency Cancel Delay Protection

**What was changed:**
Added a 12-hour mandatory delay before `emergencyCancelDrawing()` can be executed.

**Why this matters:**
- Prevents admin from canceling a draw immediately after triggering it
- Builds user trust by ensuring admin cannot cancel based on seeing unfavorable winners
- VRF normally responds in <5 minutes, so 12 hours proves genuine failure
- Still allows legitimate emergency recovery if VRF truly fails

**Code changes:**

1. **Added new constants and state variables** (lines 460-468):
   - `EMERGENCY_CANCEL_DELAY` constant set to 12 hours
   - `drawTriggeredAt` mapping to track when each draw was triggered

2. **Added new custom error** (line 796):
   - `TooEarlyForEmergencyCancel()` - thrown if trying to emergency cancel before delay expires

3. **Modified `triggerDraw()` function** (line 1043):
   - Now records `block.timestamp` when draw is triggered
   - Stores in `drawTriggeredAt[_raffleId]`

4. **Modified `emergencyCancelDrawing()` function** (lines 1781-1783):
   - Added time check before allowing cancellation
   - Must wait `EMERGENCY_CANCEL_DELAY` (12 hours) after draw was triggered
   - Reverts with `TooEarlyForEmergencyCancel()` if called too early

**Security impact:**
- 🟡 MEDIUM risk → 🟢 LOW risk
- Prevents potential admin abuse
- Aligns with DeFi best practices
- Production-ready implementation

**Backward compatibility:**
- ✅ Fully backward compatible
- No changes to external interfaces
- Existing functionality unchanged
- Only adds delay constraint to emergency function

**Testing recommendations:**
- Test that emergency cancel fails before 12 hours
- Test that emergency cancel succeeds after 12 hours
- Use Hardhat `time.increase()` to test time-based logic
- Verify VRF callback still works normally

---

## [2.0.0] - 2026-01-28

### Initial Release

- Multi-winner raffle system
- Chainlink VRF integration for provably fair randomness
- 5% maximum platform fee (hardcoded)
- Comprehensive refund system
- Emergency pause functionality
- Full test coverage
