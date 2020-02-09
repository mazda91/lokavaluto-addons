// TRANSFER
import static groovyx.net.http.ContentType.*
import static groovyx.net.http.Method.*
import groovyx.net.http.HTTPBuilder

import java.util.concurrent.CountDownLatch

import org.cyclos.model.ValidationException

import org.cyclos.entities.banking.RecurringPaymentTransfer
import org.cyclos.entities.banking.ScheduledPaymentInstallmentTransfer
import org.cyclos.entities.banking.FailedPaymentOccurrence 

def url = ''
def jsonBody =  []

def tf = scriptHelper.wrap(transfer)

if (! ((transfer instanceof RecurringPaymentTransfer) | (transfer instanceof ScheduledPaymentInstallmentTransfer) | (transfer instanceof FailedPaymentOccurrence)) ){
    return
}



if( (transfer instanceof RecurringPaymentTransfer) | (transfer instanceof FailedPaymentOccurrence) ){
	url = 'http://front:8000/operations/sync/recurring' 
    jsonBody =  [
        paymentID: maskId(tf.transferId),
        transactionID: maskId(tf.recurringPayment.id),
        amount: tf.amount,
        description: tf.recurringPayment.description,
        fromAccountNumber: tf.from.number,
        toAccountNumber: tf.to.number,
        status: tf.status
	]    

} else {
	url = 'http://front:8000/operations/sync/scheduled'
    jsonBody =  [
        paymentID: maskId(tf.installment.transferId),
        transactionID: maskId(tf.transactionId),
        amount: tf.amount,
        description: tf.transaction.description,
        fromAccountNumber: tf.from.number,
        toAccountNumber: tf.to.number,
        status: tf.installment.status
	]
}


// Send the POST request
def http = new HTTPBuilder(url)
http.headers["Content-Type"] = "application/json; charset=UTF-8"
def responseJson = null
def responseError = []

scriptHelper.addOnCommit {
    CountDownLatch latch = new CountDownLatch(1)
    def error = false
    http.request(POST, JSON) {
        body = jsonBody
        
       response.success = { resp, json ->
        	responseJson = json
        	latch.countDown()
        }
        response.failure = { resp ->
        	responseError << resp.statusLine.statusCode
        	responseError << resp.statusLine.reasonPhrase
        	latch.countDown()
        }
    }
    //Await for the response
	latch.await()
	if (!responseError.empty) {
		throw new RuntimeException("Error making Cyclos sync to ${url}"
			+ ", got error code ${responseError[0]}: ${responseError[1]}")
	}
	return responseJson
}
