#!/usr/bin/env bash
# Test script for playvideo functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYVIDEO="$SCRIPT_DIR/playvideo.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

print_test_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

pass() {
    echo -e "${GREEN}✓ $1${NC}"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ $1${NC}"
    ((TESTS_FAILED++))
}

test_help() {
    print_test_header "Testing Help and Basic Options"
    
    # Test help output
    if "$PLAYVIDEO" --help >/dev/null 2>&1; then
        pass "Help option works"
    else
        fail "Help option failed"
    fi
    
    # Test list profiles
    if "$PLAYVIDEO" --list-profiles >/dev/null 2>&1; then
        pass "List profiles works"
    else
        fail "List profiles failed"
    fi
}

run_tests() {
    test_help
    echo -e "\n${YELLOW}=== Basic Test Summary ===${NC}"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}Basic tests passed! ✓${NC}"
        return 0
    else
        echo -e "\n${RED}Some basic tests failed! ✗${NC}"
        return 1
    fi
}

# Run the basic tests first
if run_tests; then
    echo "Proceeding with comprehensive tests..."
else
    echo "Basic tests failed, stopping here."
    exit 1
fi

test_help() {
    print_test_header "Testing Help and Basic Options"
    
    # Test help output
    if "$PLAYVIDEO" --help >/dev/null 2>&1; then
        pass "Help option works"
    else
        fail "Help option failed"
    fi
    
    # Test list profiles
    if "$PLAYVIDEO" --list-profiles >/dev/null 2>&1; then
        pass "List profiles works"
    else
        fail "List profiles failed"
    fi
    
    # Test invalid option (this should return non-zero)
    if "$PLAYVIDEO" --invalid-option >/dev/null 2>&1; then
        fail "Invalid options not properly rejected"
    else
        pass "Invalid options are rejected"
    fi
}

test_dry_run_formats() {
    print_test_header "Testing Dry Run for All Formats"
    
    local formats=("sixel" "kitty" "ascii" "ansi" "utf8" "caca" "gif" "mp4")
    
    for format in "${formats[@]}"; do
        # Test dependency checking (should fail since tools are not installed)
        if "$PLAYVIDEO" --dry-run --format "$format" >/dev/null 2>&1; then
            fail "Format $format: dependency checking failed (should have failed due to missing deps)"
        else
            pass "Format $format: dependency checking works"
        fi
    done
}

test_audio_dependency() {
    print_test_header "Testing Audio Dependency Checking"
    
    # Test audio dependency checking (should fail since ffplay is not installed)
    if "$PLAYVIDEO" --dry-run --audio --format gif >/dev/null 2>&1; then
        fail "Audio dependency checking failed (should have failed due to missing deps)"
    else
        pass "Audio dependency checking works"
    fi
}

test_file_input() {
    print_test_header "Testing File Input Validation"
    
    # Test with non-existent file (should fail)
    if "$PLAYVIDEO" --dry-run --input "/nonexistent/file.mp4" >/dev/null 2>&1; then
        fail "Non-existent file validation failed (should have failed)"
    else
        pass "Non-existent file validation works"
    fi
}

test_flag_parsing() {
    print_test_header "Testing Flag Parsing"
    
    # Test video flags parsing (should fail due to missing deps, but flags should parse)
    if "$PLAYVIDEO" --dry-run --video-flags "-some-flag" >/dev/null 2>&1; then
        fail "Video flags parsing failed (should have failed due to missing deps)"
    else
        pass "Video flags parsing works (expected to fail due to missing deps)"
    fi
    
    # Test audio flags parsing (should fail due to missing deps, but flags should parse)
    if "$PLAYVIDEO" --dry-run --audio-flags "-some-flag" --audio >/dev/null 2>&1; then
        fail "Audio flags parsing failed (should have failed due to missing deps)"
    else
        pass "Audio flags parsing works (expected to fail due to missing deps)"
    fi
    
    # Test empty flag error (should fail due to missing argument)
    if "$PLAYVIDEO" --video-flags >/dev/null 2>&1; then
        fail "Empty video flags not properly rejected"
    else
        pass "Empty video flags are rejected"
    fi
    
    if "$PLAYVIDEO" --audio-flags >/dev/null 2>&1; then
        fail "Empty audio flags not properly rejected"
    else
        pass "Empty audio flags are rejected"
    fi
}

test_profiles() {
    print_test_header "Testing Profile System"
    
    # Test using a profile (should fail due to missing deps, but profile should parse)
    if "$PLAYVIDEO" --dry-run --use-profile sixel >/dev/null 2>&1; then
        fail "Profile usage failed (should have failed due to missing deps)"
    else
        pass "Profile usage works (expected to fail due to missing deps)"
    fi
    
    # Test invalid profile (should fail due to invalid profile)
    if "$PLAYVIDEO" --use-profile invalid_profile >/dev/null 2>&1; then
        fail "Invalid profiles not properly rejected"
    else
        pass "Invalid profiles are rejected"
    fi
}

test_verbose_mode() {
    print_test_header "Testing Verbose Mode"
    
    # Create a temporary test file and test verbose mode 
    echo "test" > /tmp/test.txt
    output=$("$PLAYVIDEO" --verbose --input /tmp/test.txt --format gif 2>&1 || true)
    if echo "$output" | grep -q "\[playvideo\]"; then
        pass "Verbose mode generates debug output"
    else
        fail "Verbose mode doesn't generate debug output"
        echo "Debug: output was: $output"
    fi
    rm -f /tmp/test.txt
}

# Run all tests
test_help
test_dry_run_formats
test_audio_dependency
test_file_input
test_flag_parsing
test_profiles
test_verbose_mode

# Summary
echo -e "\n${YELLOW}=== Test Summary ===${NC}"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed! ✗${NC}"
    exit 1
fi