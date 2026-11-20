/// Супермаркет буюртмаси ҳолати — 5 босқич (эга 2026-11-20):
/// қабул қилинди → йиғилмоқда → тайёр → курьерда → етказилди.
///
/// NEEDS CONFIRMATION: сервер статус сатрлари шартномада йўқ. Мавжуд `orders` статуслари
/// (`accepted`, `ready`, `in_delivery`, `delivered`) ва эҳтимолий синонимлар қабул қилинади;
/// номаълум статус — `null` (UI уни кўрсатмайди, crash йўқ).
library;

enum SmOrderStep { accepted, preparing, ready, courier, delivered }

const kSmOrderStepKeys = <SmOrderStep, String>{
  SmOrderStep.accepted: 'sm_step_accepted',
  SmOrderStep.preparing: 'sm_step_preparing',
  SmOrderStep.ready: 'sm_step_ready',
  SmOrderStep.courier: 'sm_step_courier',
  SmOrderStep.delivered: 'sm_step_delivered',
};

SmOrderStep? smOrderStep(String status) {
  switch (status.trim().toLowerCase()) {
    case 'new':
    case 'accepted':
    case 'paid':
      return SmOrderStep.accepted;
    case 'preparing':
    case 'picking':
    case 'cooking':
      return SmOrderStep.preparing;
    case 'ready':
    case 'ready_for_pickup':
      return SmOrderStep.ready;
    case 'courier':
    case 'courier_assigned':
    case 'picked_up':
    case 'in_delivery':
    case 'on_the_way':
      return SmOrderStep.courier;
    case 'delivered':
    case 'completed':
    case 'settled':
      return SmOrderStep.delivered;
  }
  return null;
}

/// Бу буюртма супермаркетникими (`orders.type`). NEEDS CONFIRMATION: сервер `type: 'supermarket'`
/// ёзади деб келишилиши керак.
bool isSupermarketOrderType(String type) => type == 'supermarket';
