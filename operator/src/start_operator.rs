use SereeServiceManager::Task;
use alloy_sol_types::{sol, SolEvent};
use once_cell::sync::Lazy;
use std::{env, str::FromStr};
use notary_server::{NotarizationProperties, run_server};


sol!(
    #[allow(missing_docs)]
    #[sol(rpc)]
    SereeServiceManager,
    "json_abi/SereeServiceManager.json"
);

static KEY: Lazy<String> = Lazy::new(|| {
    env::var("HOLESKY_PRIVATE_KEY").expect("failed to retrieve private key")
});

pub static RPC_URL: Lazy<String> = Lazy::new(|| {
    env::var("HOLESKY_RPC_URL").expect("failed to retrieve rpc url")
});

pub static SEREE_CONTRACT_ADDRESS: Lazy<String> = Lazy::new(|| {
    env::var("SEREE_CONTRACT_ADDRESS").expect("failed to retrieve contract address")
});

static DELEGATION_MANAGER_CONTRACT_ADDRESS: Lazy<String> = Lazy::new(|| {
    env::var("HOLESKY_DELEGATION_MANAGER_ADDRESS")
        .expect("failed to get delegation manager contract address from env")
});

static STAKE_REGISTRY_CONTRACT_ADDRESS: Lazy<String> = Lazy::new(|| {
    env::var("HOLESKY_STAKE_REGISTRY_ADDRESS")
        .expect("failed to get stake registry contract address from env")
});

static AVS_DIRECTORY_CONTRACT_ADDRESS: Lazy<String> = Lazy::new(|| {
    env::var("HOLESKY_AVS_DIRECTORY_ADDRESS")
        .expect("failed to get delegation manager contract address from env")
});

