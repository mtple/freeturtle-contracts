import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

const key = generatePrivateKey();
const account = privateKeyToAccount(key);

console.log("Address:    ", account.address);
console.log("Private Key:", key);
