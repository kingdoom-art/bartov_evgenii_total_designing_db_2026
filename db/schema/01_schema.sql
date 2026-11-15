CREATE SCHEMA bartov_food;

CREATE TYPE bartov_food.restaurant_status AS ENUM ('активен', 'неактивен');
CREATE TYPE bartov_food.product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив');
CREATE TYPE bartov_food.courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');
CREATE TYPE bartov_food.order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
CREATE TYPE bartov_food.order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');
CREATE TYPE bartov_food.payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');
CREATE TYPE bartov_food.payment_type AS ENUM ('карта', 'наличные', 'безнал');
CREATE TYPE bartov_food.review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');

CREATE TABLE bartov_food.client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(100) NOT NULL UNIQUE CHECK (login ~ '^[^[:space:]@]+@[^[:space:]@.]+(\.[^[:space:]@.]+)+$'),
    password varchar(32) NOT NULL CHECK (password ~ '^[0-9a-f]{32}$'),
    phone_number varchar(20) NOT NULL UNIQUE
);

CREATE TABLE bartov_food.address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(200) NOT NULL,
    house_number varchar(30) NOT NULL,
    apartment_office varchar(30)
);

CREATE TABLE bartov_food.client_address (
    client_id uuid NOT NULL REFERENCES bartov_food.client (client_id),
    address_id uuid NOT NULL REFERENCES bartov_food.address (address_id),
    PRIMARY KEY (client_id, address_id)
);

CREATE TABLE bartov_food.restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(200) NOT NULL,
    address_id uuid NOT NULL UNIQUE REFERENCES bartov_food.address (address_id),
    description text,
    work_start time NOT NULL,
    work_end time NOT NULL,
    inn varchar(12) NOT NULL CHECK (inn ~ '^([0-9]{10}|[0-9]{12})$'),
    ogrn varchar(13) NOT NULL CHECK (ogrn ~ '^[0-9]{13}$'),
    settlement_account varchar(20) NOT NULL CHECK (settlement_account ~ '^[0-9]{20}$'),
    rating numeric(4, 2) CHECK (rating BETWEEN 0 AND 5),
    status bartov_food.restaurant_status NOT NULL DEFAULT 'активен',
    CHECK (work_end > work_start)
);

CREATE TABLE bartov_food.courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(200) NOT NULL,
    phone_number varchar(20) NOT NULL,
    status bartov_food.courier_status NOT NULL DEFAULT 'свободен',
    hire_date date NOT NULL DEFAULT current_date,
    dismissal_date date,
    coefficient numeric(3, 1) NOT NULL DEFAULT 0.1 CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL),
    CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)
);

CREATE TABLE bartov_food.courier_pay (
    courier_pay_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    year integer NOT NULL,
    month integer NOT NULL CHECK (month BETWEEN 1 AND 12),
    courier_id uuid NOT NULL REFERENCES bartov_food.courier (courier_id),
    amount numeric(16, 2) NOT NULL CHECK (amount >= 0),
    coefficient_used numeric(3, 1) NOT NULL CHECK (coefficient_used BETWEEN 0.1 AND 0.5),
    UNIQUE (year, month, courier_id)
);

CREATE TABLE bartov_food.product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(200) NOT NULL
);

CREATE TABLE bartov_food.product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(200) NOT NULL,
    product_category_id uuid NOT NULL REFERENCES bartov_food.product_category (product_category_id),
    price numeric(14, 2) NOT NULL CHECK (price >= 0),
    restaurant_id uuid NOT NULL REFERENCES bartov_food.restaurant (restaurant_id),
    rating numeric(4, 2) CHECK (rating BETWEEN 0 AND 5),
    status bartov_food.product_status NOT NULL DEFAULT 'доступно',
    description text
);

CREATE TABLE bartov_food.product_photo (
    photo_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_id uuid NOT NULL REFERENCES bartov_food.product (product_id),
    photo_url text NOT NULL
);

CREATE TABLE bartov_food."order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL REFERENCES bartov_food.courier (courier_id),
    client_id uuid NOT NULL REFERENCES bartov_food.client (client_id),
    address_id uuid NOT NULL REFERENCES bartov_food.address (address_id),
    restaurant_id uuid NOT NULL REFERENCES bartov_food.restaurant (restaurant_id),
    order_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp,
    order_amount numeric(14, 2) NOT NULL CHECK (order_amount >= 0),
    commission numeric(14, 2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount numeric(14, 2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED,
    status bartov_food.order_status NOT NULL DEFAULT 'создан',
    pay_status bartov_food.order_pay_status NOT NULL DEFAULT 'ожидает',
    description text,
    CHECK (total_amount >= 1000),
    CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL)
);

CREATE TABLE bartov_food.payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES bartov_food."order" (order_id),
    type bartov_food.payment_type NOT NULL,
    amount numeric(14, 2) NOT NULL CHECK (amount >= 0),
    transaction_reference varchar(200) NOT NULL UNIQUE,
    transaction_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    status bartov_food.payment_status NOT NULL DEFAULT 'в_обработке'
);
CREATE UNIQUE INDEX payment_one_success_per_order ON bartov_food.payment (order_id)
    WHERE status = 'успех';

CREATE TABLE bartov_food.order_structure (
    order_structure_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES bartov_food."order" (order_id),
    product_id uuid NOT NULL REFERENCES bartov_food.product (product_id),
    quantity numeric(14, 3) NOT NULL CHECK (quantity > 0),
    unit_price numeric(14, 2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (order_id, product_id)
);

CREATE TABLE bartov_food.review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL REFERENCES bartov_food.client (client_id),
    review_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    entity_id uuid NOT NULL,
    entity_type bartov_food.review_entity_type NOT NULL,
    order_id uuid NOT NULL REFERENCES bartov_food."order" (order_id),
    description text,
    rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
    UNIQUE (order_id, entity_type, entity_id)
);

CREATE TABLE bartov_food.review_photo (
    photo_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    review_id uuid NOT NULL REFERENCES bartov_food.review (review_id),
    photo_url text NOT NULL
);
