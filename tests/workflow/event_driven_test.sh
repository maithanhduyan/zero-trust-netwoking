#!/bin/bash
# ==============================================================================
# Event-Driven Architecture Test Suite
# Tests the complete Event-Driven Zero Trust implementation:
# - Event Bus & Event Store
# - User/Group/Policy Management
# - Access Evaluation
# - WebSocket & Real-time Updates
# ==============================================================================

# Don't exit on error - we want to continue and report
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
HUB_URL="${HUB_URL:-http://localhost:8000}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
DB_PATH="${DB_PATH:-/var/lib/zero-trust/zerotrust.db}"

# Load config from file if exists
[ -f /etc/zerotrust/ztctl.conf ] && source /etc/zerotrust/ztctl.conf
[ -f /opt/zero-trust/control-plane/.env ] && source /opt/zero-trust/control-plane/.env
ADMIN_TOKEN="${ADMIN_TOKEN:-$ADMIN_SECRET}"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# ==============================================================================
# Helper Functions
# ==============================================================================

log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD} $1 ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_test() {
    ((TESTS_TOTAL++))
    echo -e "\n${BLUE}▶ Test $TESTS_TOTAL:${NC} $1"
}

log_pass() {
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
}

log_fail() {
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗ FAIL${NC}: $1"
}

log_info() {
    echo -e "  ${YELLOW}ℹ${NC} $1"
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    local url="${HUB_URL}/api/v1${endpoint}"

    local args=("-s" "-X" "$method" "-H" "X-Admin-Token: ${ADMIN_TOKEN}" "-H" "Content-Type: application/json")
    [ -n "$data" ] && args+=("-d" "$data")

    curl "${args[@]}" "$url" 2>&1
}

check_jq() {
    command -v jq &>/dev/null || {
        echo -e "${RED}Error: jq is required. Install with: apt install jq${NC}"
        exit 1
    }
}

check_prereqs() {
    log_section "Checking Prerequisites"

    check_jq
    log_pass "jq is installed"

    # Check API connectivity
    local health=$(curl -s "${HUB_URL}/health" 2>&1)
    if echo "$health" | grep -q "healthy"; then
        log_pass "Control Plane API is reachable"
    else
        log_fail "Cannot reach Control Plane at $HUB_URL"
        echo "Response: $health"
        exit 1
    fi

    # Check admin token
    local test_resp=$(api_call GET "/admin/nodes")
    if echo "$test_resp" | grep -q "error"; then
        log_fail "Admin token is invalid"
        exit 1
    else
        log_pass "Admin token is valid"
    fi
}

# ==============================================================================
# Test: User Management
# ==============================================================================

test_user_management() {
    log_section "Testing User Management"

    local timestamp=$(date +%s)
    local test_user="test-user-${timestamp}"
    local test_email="test${timestamp}@example.com"

    # Test: Create User
    log_test "Create new user"
    local create_resp=$(api_call POST "/access/users" "{\"user_id\":\"$test_user\",\"email\":\"$test_email\",\"display_name\":\"Test User\",\"department\":\"Testing\"}")

    if echo "$create_resp" | jq -e '.id' > /dev/null 2>&1; then
        log_pass "User created: $test_user"
        local user_db_id=$(echo "$create_resp" | jq -r '.id')
    else
        log_fail "Failed to create user"
        echo "$create_resp" | jq '.' 2>/dev/null || echo "$create_resp"
        return 1
    fi

    # Test: Get User
    log_test "Get user details"
    local get_resp=$(api_call GET "/access/users/$test_user")
    if echo "$get_resp" | jq -e '.user_id' > /dev/null 2>&1; then
        log_pass "Retrieved user details"
    else
        log_fail "Failed to get user"
    fi

    # Test: List Users
    log_test "List users"
    local list_resp=$(api_call GET "/access/users")
    local user_count=$(echo "$list_resp" | jq 'length' 2>/dev/null || echo 0)
    if [ "$user_count" -gt 0 ]; then
        log_pass "Listed $user_count users"
    else
        log_fail "Failed to list users"
    fi

    # Store for later tests
    export TEST_USER="$test_user"
    export TEST_USER_DB_ID="$user_db_id"
}

# ==============================================================================
# Test: Group Management
# ==============================================================================

test_group_management() {
    log_section "Testing Group Management"

    local timestamp=$(date +%s)
    local test_group="test-group-${timestamp}"

    # Test: Create Group
    log_test "Create new group"
    local create_resp=$(api_call POST "/access/groups" "{\"name\":\"$test_group\",\"display_name\":\"Test Group\",\"description\":\"Test group for automated testing\"}")

    if echo "$create_resp" | jq -e '.id' > /dev/null 2>&1; then
        log_pass "Group created: $test_group"
        local group_db_id=$(echo "$create_resp" | jq -r '.id')
    else
        log_fail "Failed to create group"
        echo "$create_resp" | jq '.' 2>/dev/null || echo "$create_resp"
        return 1
    fi

    # Test: Add User to Group
    log_test "Add user to group"
    local add_resp=$(api_call POST "/access/groups/$test_group/members" "{\"user_id\":\"$TEST_USER\"}")
    if echo "$add_resp" | grep -q "success.*true"; then
        log_pass "Added $TEST_USER to $test_group"
    else
        log_fail "Failed to add user to group"
        echo "$add_resp"
    fi

    # Test: List Group Members
    log_test "List group members"
    local members_resp=$(api_call GET "/access/groups/$test_group/members")
    if echo "$members_resp" | grep -q "$TEST_USER"; then
        log_pass "User appears in group members"
    else
        log_fail "User not found in group members"
    fi

    # Test: Get User's Groups
    log_test "Get user's groups"
    local user_groups=$(api_call GET "/access/users/$TEST_USER/groups")
    if echo "$user_groups" | grep -q "$test_group"; then
        log_pass "Group appears in user's groups"
    else
        log_fail "Group not found in user's groups"
    fi

    # Store for later tests
    export TEST_GROUP="$test_group"
    export TEST_GROUP_DB_ID="$group_db_id"
}

# ==============================================================================
# Test: Access Policy Management
# ==============================================================================

test_access_policies() {
    log_section "Testing Access Policies"

    local timestamp=$(date +%s)
    local policy_name="test-policy-${timestamp}"

    # Test: Create Access Policy (Group -> Domain)
    log_test "Create access policy for group"
    local create_resp=$(api_call POST "/access/policies" "{
        \"name\":\"$policy_name\",
        \"description\":\"Test policy for automated testing\",
        \"subject_type\":\"group\",
        \"subject_id\":$TEST_GROUP_DB_ID,
        \"resource_type\":\"domain\",
        \"resource_value\":\"*.test-internal.example.com\",
        \"action\":\"allow\",
        \"priority\":100
    }")

    if echo "$create_resp" | jq -e '.id' > /dev/null 2>&1; then
        log_pass "Access policy created: $policy_name"
        export TEST_POLICY_ID=$(echo "$create_resp" | jq -r '.id')
    else
        log_fail "Failed to create access policy"
        echo "$create_resp" | jq '.' 2>/dev/null || echo "$create_resp"
        return 1
    fi

    # Test: List Policies
    log_test "List access policies"
    local list_resp=$(api_call GET "/access/policies")
    local policy_count=$(echo "$list_resp" | jq 'length' 2>/dev/null || echo 0)
    if [ "$policy_count" -gt 0 ]; then
        log_pass "Listed $policy_count policies"
    else
        log_fail "Failed to list policies"
    fi
}

# ==============================================================================
# Test: Access Evaluation
# ==============================================================================

test_access_evaluation() {
    log_section "Testing Access Evaluation"

    # Test: Evaluate access for user in group (should ALLOW)
    log_test "Evaluate access for user in group (should ALLOW)"
    local eval_resp=$(api_call POST "/access/evaluate" "{
        \"user_id\":\"$TEST_USER\",
        \"resource_type\":\"domain\",
        \"resource_value\":\"api.test-internal.example.com\"
    }")

    local allowed=$(echo "$eval_resp" | jq -r '.allowed')
    local action=$(echo "$eval_resp" | jq -r '.action')

    if [ "$allowed" = "true" ] && [ "$action" = "allow" ]; then
        log_pass "Access ALLOWED for matching domain pattern"
    else
        log_fail "Expected ALLOW but got: allowed=$allowed, action=$action"
        echo "$eval_resp" | jq '.'
    fi

    # Test: Evaluate access for non-matching domain (should DENY)
    log_test "Evaluate access for non-matching domain (should DENY)"
    local deny_resp=$(api_call POST "/access/evaluate" "{
        \"user_id\":\"$TEST_USER\",
        \"resource_type\":\"domain\",
        \"resource_value\":\"api.external.example.com\"
    }")

    local denied=$(echo "$deny_resp" | jq -r '.allowed')
    if [ "$denied" = "false" ]; then
        log_pass "Access DENIED for non-matching domain (default deny)"
    else
        log_fail "Expected DENY but got: allowed=$denied"
    fi

    # Test: Evaluate access for unknown user (should DENY)
    log_test "Evaluate access for unknown user (should DENY)"
    local unknown_resp=$(api_call POST "/access/evaluate" "{
        \"user_id\":\"unknown-user-does-not-exist\",
        \"resource_type\":\"domain\",
        \"resource_value\":\"api.test-internal.example.com\"
    }")

    local unknown_allowed=$(echo "$unknown_resp" | jq -r '.allowed')
    if [ "$unknown_allowed" = "false" ]; then
        log_pass "Access DENIED for unknown user"
    else
        log_fail "Expected DENY for unknown user but got: allowed=$unknown_allowed"
    fi
}

# ==============================================================================
# Test: Event Store
# ==============================================================================

test_event_store() {
    log_section "Testing Event Store"

    # Test: Check events were persisted
    log_test "Verify events are being persisted to EventStore"

    if [ -f "$DB_PATH" ]; then
        local event_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM event_store;" 2>/dev/null || echo 0)

        if [ "$event_count" -gt 0 ]; then
            log_pass "EventStore has $event_count events"
        else
            log_fail "EventStore is empty"
        fi

        # Test: Check for specific event types
        log_test "Check for UserCreated events"
        local user_events=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM event_store WHERE event_type='UserCreated';" 2>/dev/null || echo 0)
        if [ "$user_events" -gt 0 ]; then
            log_pass "Found $user_events UserCreated events"
        else
            log_fail "No UserCreated events found"
        fi

        log_test "Check for GroupCreated events"
        local group_events=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM event_store WHERE event_type='GroupCreated';" 2>/dev/null || echo 0)
        if [ "$group_events" -gt 0 ]; then
            log_pass "Found $group_events GroupCreated events"
        else
            log_fail "No GroupCreated events found"
        fi

        log_test "Check for PolicyCreated events"
        local policy_events=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM event_store WHERE event_type='PolicyCreated';" 2>/dev/null || echo 0)
        if [ "$policy_events" -gt 0 ]; then
            log_pass "Found $policy_events PolicyCreated events"
        else
            log_fail "No PolicyCreated events found"
        fi

        # Show recent events
        log_info "Recent events in EventStore:"
        sqlite3 -header -column "$DB_PATH" "SELECT event_type, aggregate_type, aggregate_id, created_at FROM event_store ORDER BY id DESC LIMIT 5;" 2>/dev/null | while read -r line; do
            echo "    $line"
        done

    else
        log_fail "Database file not found: $DB_PATH"
    fi
}

# ==============================================================================
# Test: Client Device with Policy
# ==============================================================================

test_client_device_policy() {
    log_section "Testing Client Device with Policy Integration"

    local timestamp=$(date +%s)
    local device_name="test-device-${timestamp}"

    # Test: Create client device for our test user
    log_test "Create client device for test user"
    local create_resp=$(api_call POST "/client/devices" "{
        \"device_name\":\"$device_name\",
        \"device_type\":\"mobile\",
        \"user_id\":\"$TEST_USER\",
        \"tunnel_mode\":\"full\",
        \"expires_days\":1
    }")

    if echo "$create_resp" | jq -e '.id' > /dev/null 2>&1; then
        log_pass "Client device created: $device_name"
        local device_id=$(echo "$create_resp" | jq -r '.id')
        local overlay_ip=$(echo "$create_resp" | jq -r '.overlay_ip')
        log_info "Device ID: $device_id, IP: $overlay_ip"
    else
        log_fail "Failed to create client device"
        echo "$create_resp" | jq '.' 2>/dev/null || echo "$create_resp"
        return 1
    fi

    # Test: Verify ClientDeviceCreated event
    log_test "Verify ClientDeviceCreated event was persisted"
    if [ -f "$DB_PATH" ]; then
        local device_events=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM event_store WHERE event_type='ClientDeviceCreated';" 2>/dev/null || echo 0)
        if [ "$device_events" -gt 0 ]; then
            log_pass "Found $device_events ClientDeviceCreated events"
        else
            log_fail "No ClientDeviceCreated events found"
        fi
    fi

    # Store for cleanup
    export TEST_DEVICE_ID="$device_id"
}

# ==============================================================================
# Test: ztctl CLI
# ==============================================================================

test_ztctl_cli() {
    log_section "Testing ztctl CLI"

    local ztctl="/home/zero-trust-netwoking/scripts/ztctl"

    if [ ! -f "$ztctl" ]; then
        log_fail "ztctl not found at $ztctl"
        return 1
    fi

    # Test: Version
    log_test "ztctl version"
    local version=$($ztctl version 2>&1)
    if echo "$version" | grep -q "1.2.0"; then
        log_pass "ztctl version 1.2.0"
    else
        log_fail "Unexpected version: $version"
    fi

    # Test: User list command
    log_test "ztctl user list"
    export HUB_URL ADMIN_TOKEN
    local user_list=$($ztctl user list 2>&1)
    if echo "$user_list" | grep -q "USERS"; then
        log_pass "ztctl user list works"
    else
        log_fail "ztctl user list failed"
    fi

    # Test: Group list command
    log_test "ztctl group list"
    local group_list=$($ztctl group list 2>&1)
    if echo "$group_list" | grep -q "GROUPS"; then
        log_pass "ztctl group list works"
    else
        log_fail "ztctl group list failed"
    fi

    # Test: Access list command
    log_test "ztctl access list"
    local access_list=$($ztctl access list 2>&1)
    if echo "$access_list" | grep -q "ACCESS POLICIES"; then
        log_pass "ztctl access list works"
    else
        log_fail "ztctl access list failed"
    fi

    # Test: Access eval command
    log_test "ztctl access eval"
    local eval_result=$($ztctl access eval "$TEST_USER" "api.test-internal.example.com" 2>&1)
    if echo "$eval_result" | grep -q "ALLOWED"; then
        log_pass "ztctl access eval works (user has access)"
    else
        log_fail "ztctl access eval unexpected result: $eval_result"
    fi
}

# ==============================================================================
# Cleanup
# ==============================================================================

cleanup_test_data() {
    log_section "Cleaning Up Test Data"

    # Delete test policy
    if [ -n "$TEST_POLICY_ID" ]; then
        log_test "Delete test policy"
        api_call DELETE "/access/policies/$TEST_POLICY_ID" > /dev/null 2>&1
        log_pass "Deleted policy $TEST_POLICY_ID"
    fi

    # Revoke test device
    if [ -n "$TEST_DEVICE_ID" ]; then
        log_test "Revoke test device"
        api_call DELETE "/client/devices/$TEST_DEVICE_ID" > /dev/null 2>&1
        log_pass "Revoked device $TEST_DEVICE_ID"
    fi

    # Remove user from group
    if [ -n "$TEST_USER" ] && [ -n "$TEST_GROUP" ]; then
        log_test "Remove user from group"
        api_call DELETE "/access/groups/$TEST_GROUP/members/$TEST_USER" > /dev/null 2>&1
        log_pass "Removed $TEST_USER from $TEST_GROUP"
    fi

    # Delete test group
    if [ -n "$TEST_GROUP" ]; then
        log_test "Delete test group"
        api_call DELETE "/access/groups/$TEST_GROUP" > /dev/null 2>&1
        log_pass "Deleted group $TEST_GROUP"
    fi

    # Delete test user
    if [ -n "$TEST_USER" ]; then
        log_test "Delete test user"
        api_call DELETE "/access/users/$TEST_USER" > /dev/null 2>&1
        log_pass "Deleted user $TEST_USER"
    fi
}

# ==============================================================================
# Summary
# ==============================================================================

print_summary() {
    log_section "Test Summary"

    echo ""
    echo -e "${BOLD}Total Tests:${NC}  $TESTS_TOTAL"
    echo -e "${GREEN}Passed:${NC}       $TESTS_PASSED"
    echo -e "${RED}Failed:${NC}       $TESTS_FAILED"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        return 1
    fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    echo -e "${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║           Event-Driven Architecture Test Suite                           ║"
    echo "║           Zero Trust Network - Comprehensive Tests                        ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Started: $(date)"
    echo "API URL: $HUB_URL"
    echo ""

    # Run tests
    check_prereqs
    test_user_management
    test_group_management
    test_access_policies
    test_access_evaluation
    test_event_store
    test_client_device_policy
    test_ztctl_cli

    # Cleanup (optional - comment out to keep test data)
    cleanup_test_data

    # Summary
    print_summary
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
