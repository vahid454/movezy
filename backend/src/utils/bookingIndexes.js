/**
 * Removes legacy MongoDB 2dsphere indexes on whole `pickup` / `dropoff`
 * subdocuments. Those cause "unknown GeoJSON type" on insert because GeoJSON
 * must be `{ type, coordinates }` only — not `{ address, location }`.
 */
async function dropLegacyBookingGeoIndexes(mongooseConnection) {
  const coll = mongooseConnection.collection('bookings');
  let indexes;
  try {
    indexes = await coll.indexes();
  } catch (err) {
    console.warn('bookingIndexes: could not list indexes', err.message);
    return;
  }
  for (const idx of indexes) {
    const name = idx.name;
    const key = idx.key || {};
    if (name === '_id_') continue;
    const badWholeField =
      key.pickup === '2dsphere' ||
      key.dropoff === '2dsphere';
    if (badWholeField) {
      try {
        await coll.dropIndex(name);
        console.log(`bookingIndexes: dropped invalid geo index "${name}"`);
      } catch (err) {
        console.warn(`bookingIndexes: dropIndex ${name} failed`, err.message);
      }
    }
  }
}

module.exports = { dropLegacyBookingGeoIndexes };
