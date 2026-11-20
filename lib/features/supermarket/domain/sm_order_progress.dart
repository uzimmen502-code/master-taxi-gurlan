/// Супермаркет буюртмаси ҳолати — 5 босқич (эга 2026-11-20):
/// қабул қилинди → йиғилмоқда → тайёр → курьерда → етказилди.
///
/// Сервер (supermarket.js, feat/supermarket-srv 48a7d45f): `orders` `type: 'platform'`, `subtype: 'supermarket'`;
/// `status`: new → accepted (+smWeighPending) → ready → courier/in_delivery → delivered; курьер ҳолати
/// `fulfillmentStatus`да (courier_picked / arrived / completed). Номаълум / рад / бекор — `null`.
library;

enum SmOrderStep { accepted, preparing, ready, courier, delivered }

const kSmOrderStepKeys = <SmOrderStep, String>{
  SmOrderStep.accepted: 'sm_step_accepted',
  SmOrderStep.preparing: 'sm_step_preparing',
  SmOrderStep.ready: 'sm_step_ready',
  SmOrderStep.courier: 'sm_step_courier',
  SmOrderStep.delivered: 'sm_step_delivered',
};

SmOrderStep? smOrderStep(String status, {String fulfillmentStatus = ''}) {
  final s = status.trim().toLowerCase();
  final fs = fulfillmentStatus.trim().toLowerCase();
  if (s == 'rejected' || s == 'cancelled' || fs == 'cancelled') return null;
  if (s == 'delivered' || fs == 'completed') return SmOrderStep.delivered;
  if (s == 'courier' || s == 'in_delivery' || fs == 'courier_picked' || fs == 'arrived') return SmOrderStep.courier;
  switch (s) {
    case 'new':
      return SmOrderStep.accepted; // мижоз учун: буюртма қабул қилинди (тўланди)
    case 'accepted':
      return SmOrderStep.preparing; // AVA йиғмоқда (тортиш шу босқичда)
    case 'ready':
      return SmOrderStep.ready;
  }
  return null;
}

/// Бу буюртма супермаркетникими.
bool isSupermarketOrder(String type, String subtype) => type == 'platform' && subtype == 'supermarket';
