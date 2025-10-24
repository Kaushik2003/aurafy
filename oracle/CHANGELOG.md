# Oracle Changelog

## v1.0.0 - Initial Release

### Features
- ✅ Farcaster metrics fetching via Neynar API (free tier compatible)
- ✅ Weighted aura computation with log-based normalization
- ✅ IPFS pinning for audit trail (Pinata integration)
- ✅ On-chain vault updates via ethers.js
- ✅ Command-line interface with multiple modes
- ✅ Mock mode for testing without API keys
- ✅ Dry-run mode for safe testing

### Free Tier Compatibility

The oracle has been optimized to work with Neynar's free tier API:

**What Works:**
- User profile fetching (`/v2/farcaster/user/bulk`)
- Follower count (direct)
- Verification status (power badge)
- Neynar user score (0-1 engagement metric)

**Derived Metrics:**
- **Average Likes**: Estimated from Neynar score (score * 100)
- **Follower Delta**: Calculated from score and follower/following ratio

**Not Required:**
- Premium cast feed endpoint (not available in free tier)
- Historical follower data (estimated instead)

### Testing

All tests pass:
- ✅ Clamp function
- ✅ Log-based normalization
- ✅ Mock metrics fetching
- ✅ Aura computation
- ✅ Multiple scenario validation
- ✅ Real API integration (FID 1398844)

### Usage Examples

```bash
# Test with mock data
node oracle.js --vault 0x123... --fid 12345 --mock --dry-run

# Test with real Farcaster data (free tier)
NEYNAR_API_KEY=your_key node oracle.js --vault 0x123... --fid 1398844 --dry-run

# Full execution (requires all env vars)
node oracle.js --vault 0x123... --fid 12345
```

### Known Limitations

1. **Engagement Estimation**: Since we can't access cast data in free tier, we use Neynar's user score as a proxy for engagement
2. **Follower Delta**: Estimated rather than calculated from historical data
3. **Real-time Accuracy**: Metrics are point-in-time snapshots, not averaged over time

### Future Enhancements

- [ ] Historical data tracking for accurate follower deltas
- [ ] Multi-oracle consensus mechanism
- [ ] Automated scheduling/cron integration
- [ ] Dashboard for monitoring oracle health
- [ ] Support for additional social signals
