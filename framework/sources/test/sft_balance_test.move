#[test_only]
module interest_framework::semi_fungible_balance_tests {
    use sui::test_utils::{destroy, assert_eq};

    use interest_framework::semi_fungible_balance;

    struct Token has drop {}

    #[test]
    fun test_sft_balance() {
        let balance = semi_fungible_balance::create_for_testing<Token>(10, 0);
        let another = semi_fungible_balance::create_for_testing<Token>(10, 1000);

        semi_fungible_balance::join(&mut balance, another);

        assert_eq(semi_fungible_balance::value(&balance), 1000);
        assert_eq(semi_fungible_balance::slot(&balance), 10);

        let balance1 = semi_fungible_balance::split(&mut balance, 333);
        let balance2 = semi_fungible_balance::split(&mut balance, 333);
        let balance3 = semi_fungible_balance::split(&mut balance, 334);

        semi_fungible_balance::destroy_zero(balance);

        assert_eq(semi_fungible_balance::value(&balance1), 333);
        assert_eq(semi_fungible_balance::slot(&balance1), 10);
        assert_eq(semi_fungible_balance::value(&balance2), 333);
        assert_eq(semi_fungible_balance::slot(&balance2), 10);
        assert_eq(semi_fungible_balance::value(&balance3), 334);
        assert_eq(semi_fungible_balance::slot(&balance3), 10);

        destroy(balance1);
        destroy(balance2);
        destroy(balance3);
    }
}