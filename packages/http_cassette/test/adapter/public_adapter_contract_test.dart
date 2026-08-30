import '../support/adapter_contract.dart';
import '../support/fake_http_adapter.dart';

void main() {
  runBasicPublicAdapterContract(FakeHttpAdapter.new);
}
